/*
 * Vencord, a Discord client mod
 * Copyright (c) 2026 Vendicated and contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import type { Channel, Emoji, Sticker } from "@vencord/discord-types";
import {
    EmojiStore,
    PermissionsBits,
    PermissionStore,
    SoundboardStore,
    StickersStore,
    UserSettingsActionCreators,
} from "@webpack/common";

import { canSendSoundboardAttachment } from "./_shared/soundboard/src/runtime";
import { AdaptiveRandomPicker } from "./adaptiveRandom";
import { localize } from "./localization";
import { buildGifPreviewSources, resolveGifContentUrl } from "./previewMedia";
import { buildSelectionPlan } from "./selectionPlan";
import { getRepeatStrength, settings } from "./settings";
import {
    collectChatSoundboardCandidates,
    soundboardStoreLoadingError,
    soundboardUnavailableError,
} from "./soundboardIntegration";
import type {
    ConcreteFavoriteKind,
    FavoriteCandidate,
    FavoriteDrawResult,
    FavoriteKind,
    FavoritePools,
    FrecencySettings,
    FrecencySettingsActions,
    PoolScope,
} from "./types";
import { pickUniform } from "./uniformRandom";

const concreteKinds: ConcreteFavoriteKind[] = ["gif", "emoji", "sticker", "soundboard"];
const candidatePicker = new AdaptiveRandomPicker<FavoriteCandidate>(candidate => candidate.key);
const kindPicker = new AdaptiveRandomPicker<ConcreteFavoriteKind>(kind => kind);

export function kindLabel(kind: FavoriteKind) {
    const labels: Record<FavoriteKind, [string, string]> = {
        all: ["random items", "éléments aléatoires"],
        gif: ["favorite GIFs", "GIF favoris"],
        emoji: ["favorite emojis", "emotes favorites"],
        sticker: ["favorite stickers", "stickers favoris"],
        soundboard: ["soundboard sounds", "sons du soundboard"],
    };

    return localize(...labels[kind]);
}

export function shortKindLabel(kind: ConcreteFavoriteKind) {
    const labels: Record<ConcreteFavoriteKind, [string, string]> = {
        gif: ["GIF", "GIF"],
        emoji: ["emoji", "emote"],
        sticker: ["sticker", "sticker"],
        soundboard: ["soundboard", "son"],
    };

    return localize(...labels[kind]);
}

export function selectedLeftClickKinds(channel?: Channel) {
    const enabled: Record<ConcreteFavoriteKind, boolean> = {
        gif: settings.store.sendGifsOnLeftClick,
        emoji: settings.store.sendEmojisOnLeftClick,
        sticker: settings.store.sendStickersOnLeftClick,
        soundboard: settings.store.sendSoundboardsOnLeftClick,
    };

    return concreteKinds.filter(kind => enabled[kind]
        && (kind !== "soundboard" || !channel || canAttachFiles(channel)));
}

export function selectedKindsLabel(kinds: readonly ConcreteFavoriteKind[]) {
    if (kinds.length === 0)
        return localize("nothing selected", "aucune sélection");

    return kinds.map(shortKindLabel).join(" + ");
}

function selectedPoolLabel(kind: FavoriteKind) {
    if (kind === "emoji" && settings.store.emojiPool === "all")
        return localize("usable emojis", "emotes utilisables");

    if (kind === "sticker" && settings.store.stickerPool === "all")
        return localize("usable stickers", "stickers utilisables");

    if (kind === "soundboard")
        return localize("accessible soundboard sounds", "sons du soundboard accessibles");

    if (
        kind === "all"
        && (settings.store.emojiPool === "all" || settings.store.stickerPool === "all")
    ) {
        return localize(
            "items from the selected pools",
            "éléments des listes sélectionnées",
        );
    }

    return kindLabel(kind);
}

function getFrecencySettings(): FrecencySettings | undefined {
    const actions = UserSettingsActionCreators
        .FrecencyUserSettingsActionCreators as FrecencySettingsActions;

    return actions.getCurrentValue?.();
}

function canUsePermission(channel: Channel, permission: bigint) {
    return channel.isPrivate() || PermissionStore.can(permission, channel);
}

export function canSendMessages(channel: Channel) {
    if (channel.isPrivate()) return true;

    const permission = channel.isThread()
        ? PermissionsBits.SEND_MESSAGES_IN_THREADS
        : PermissionsBits.SEND_MESSAGES;

    return PermissionStore.can(permission, channel);
}

export function canAttachFiles(channel: Channel) {
    return canSendSoundboardAttachment(channel);
}

function collectGifs(frecency: FrecencySettings): {
    candidates: FavoriteCandidate[];
    rawCount: number;
} {
    const entries = Object.entries(frecency.favoriteGifs?.gifs ?? {});
    const uniqueCandidates = new Map<string, FavoriteCandidate>();

    for (const [favoriteUrl, gif] of entries) {
        const contentUrl = resolveGifContentUrl(favoriteUrl, gif ?? {});
        if (!contentUrl) continue;

        const key = `gif:${contentUrl}`;
        uniqueCandidates.set(key, {
            kind: "gif",
            key,
            label: contentUrl,
            content: contentUrl,
            previewSources: buildGifPreviewSources(favoriteUrl, gif ?? {}),
        });
    }

    return {
        candidates: Array.from(uniqueCandidates.values()),
        rawCount: entries.length,
    };
}

export function formatEmoji(emoji: Emoji) {
    if (emoji.type === 0) return emoji.surrogates;

    const name = emoji.originalName || emoji.name;
    return `<${emoji.animated ? "a" : ""}:${name}:${emoji.id}>`;
}

export function isUsableEmoji(emoji: Emoji, channel: Channel): boolean {
    if (emoji.type === 0) return true;
    if (emoji.available === false) return false;
    if (!EmojiStore.getUsableCustomEmojiById(emoji.id)) return false;

    return (
        !channel.guild_id
        || emoji.guildId === channel.guild_id
        || canUsePermission(channel, PermissionsBits.USE_EXTERNAL_EMOJIS)
    );
}

function collectEmojis(frecency: FrecencySettings, channel: Channel): {
    candidates: FavoriteCandidate[];
    rawCount: number;
} {
    const favoriteKeys = frecency.favoriteEmojis?.emojis ?? [];
    const emojiContext = EmojiStore.getDisambiguatedEmojiContext(channel.guild_id ?? null);
    const scope = settings.store.emojiPool as PoolScope;
    const sourceEmojis = scope === "all"
        ? emojiContext.getDisambiguatedEmoji()
        : emojiContext.favoriteEmojisWithoutFetchingLatest;
    const uniqueCandidates = new Map<string, FavoriteCandidate>();

    for (const emoji of sourceEmojis) {
        if (!isUsableEmoji(emoji, channel)) continue;

        const content = formatEmoji(emoji);
        const identity = emoji.type === 0 ? emoji.surrogates : emoji.id;
        const key = `emoji:${identity}`;

        uniqueCandidates.set(key, {
            kind: "emoji",
            key,
            label: emoji.name,
            content,
        });
    }

    // The official context handles aliases, diversity variants and renamed emojis.
    // If its cache has not been rebuilt yet, resolve the raw setting as a fallback.
    if (scope === "favorites" && uniqueCandidates.size === 0 && favoriteKeys.length > 0) {
        for (const favoriteKey of favoriteKeys) {
            const rawKey = String(favoriteKey);
            const emoji = emojiContext.getById(rawKey) ?? emojiContext.getByName(rawKey);
            if (!emoji || !isUsableEmoji(emoji, channel)) continue;

            const content = formatEmoji(emoji);
            const identity = emoji.type === 0 ? emoji.surrogates : emoji.id;
            const key = `emoji:${identity}`;

            uniqueCandidates.set(key, {
                kind: "emoji",
                key,
                label: emoji.name,
                content,
            });
        }
    }

    return {
        candidates: Array.from(uniqueCandidates.values()),
        rawCount: scope === "all" ? sourceEmojis.length : favoriteKeys.length,
    };
}

function isUsableSticker(sticker: Sticker, channel: Channel) {
    if (sticker.available === false) return false;
    if (!("guild_id" in sticker)) return true;

    return (
        !channel.guild_id
        || sticker.guild_id === channel.guild_id
        || canUsePermission(channel, PermissionsBits.USE_EXTERNAL_STICKERS)
    );
}

function getStickerPreview(
    sticker: Sticker,
): Pick<FavoriteCandidate, "previewType" | "previewUrl"> {
    if (sticker.format_type === 4) {
        return {
            previewType: "image",
            previewUrl: `https:${window.GLOBAL_ENV.MEDIA_PROXY_ENDPOINT}/stickers/${sticker.id}.gif?size=320&lossless=true`,
        };
    }

    const isLottie = sticker.format_type === 3;
    return {
        previewType: isLottie ? "lottie" : "image",
        previewUrl: `https://${window.GLOBAL_ENV.CDN_HOST}/stickers/${sticker.id}.${isLottie ? "json" : "png"}?size=320&lossless=true`,
    };
}

function collectStickers(frecency: FrecencySettings, channel: Channel): {
    candidates: FavoriteCandidate[];
    rawCount: number;
} {
    const favoriteIds = frecency.favoriteStickers?.stickerIds ?? [];
    const uniqueCandidates = new Map<string, FavoriteCandidate>();
    const scope = settings.store.stickerPool as PoolScope;

    if (scope === "all") {
        const stickerGroups = [
            ...StickersStore.getAllGuildStickers().values(),
            ...StickersStore.getAllPackStickers().values(),
        ];
        const allStickers = stickerGroups.flat();

        for (const sticker of allStickers) {
            if (!isUsableSticker(sticker, channel)) continue;

            const key = `sticker:${sticker.id}`;
            uniqueCandidates.set(key, {
                ...getStickerPreview(sticker),
                kind: "sticker",
                key,
                label: sticker.name,
                stickerId: sticker.id,
            });
        }

        return {
            candidates: Array.from(uniqueCandidates.values()),
            rawCount: allStickers.length,
        };
    }

    for (const favoriteId of favoriteIds) {
        const stickerId = String(favoriteId);
        const sticker = StickersStore.getStickerById(stickerId);
        if (!sticker || !isUsableSticker(sticker, channel)) continue;

        const key = `sticker:${stickerId}`;
        uniqueCandidates.set(key, {
            ...getStickerPreview(sticker),
            kind: "sticker",
            key,
            label: sticker.name,
            stickerId,
        });
    }

    return {
        candidates: Array.from(uniqueCandidates.values()),
        rawCount: favoriteIds.length,
    };
}

function emptyPools(): FavoritePools {
    return {
        candidates: { gif: [], emoji: [], sticker: [], soundboard: [] },
        rawCounts: { gif: 0, emoji: 0, sticker: 0, soundboard: 0 },
        collectionErrors: {},
    };
}

export function collectFavoritePools(
    kind: FavoriteKind,
    channel: Channel,
): FavoritePools {
    const frecency = getFrecencySettings();
    const pools = emptyPools();
    const requestedKinds = kind === "all" ? concreteKinds : [kind];

    if (!frecency) {
        for (const requestedKind of requestedKinds) {
            if (requestedKind === "soundboard") {
                const result = collectChatSoundboardCandidates(channel);
                pools.candidates[requestedKind] = result.candidates;
                pools.rawCounts[requestedKind] = result.rawCount;
                if (result.error)
                    pools.collectionErrors[requestedKind] = result.error;
            } else {
                pools.collectionErrors[requestedKind] = localize(
                    "Discord has not loaded your synced favorites yet. Open an expression picker once, then try again.",
                    "Discord n'a pas encore chargé tes favoris synchronisés. Ouvre une fois un sélecteur d'expressions, puis réessaie.",
                );
            }
        }

        return pools;
    }

    for (const requestedKind of requestedKinds) {
        if (requestedKind === "soundboard") {
            const result = collectChatSoundboardCandidates(channel);
            pools.candidates[requestedKind] = result.candidates;
            pools.rawCounts[requestedKind] = result.rawCount;
            if (result.error)
                pools.collectionErrors[requestedKind] = result.error;
            continue;
        }

        const result = requestedKind === "gif"
            ? collectGifs(frecency)
            : requestedKind === "emoji"
                ? collectEmojis(frecency, channel)
                : collectStickers(frecency, channel);

        pools.candidates[requestedKind] = result.candidates;
        pools.rawCounts[requestedKind] = result.rawCount;
    }

    return pools;
}

function pickFromKind(kind: ConcreteFavoriteKind, pools: FavoritePools) {
    const candidates = pools.candidates[kind];
    return settings.store.avoidRepeats
        ? candidatePicker.take(candidates, getRepeatStrength())
        : pickUniform(candidates);
}

function pickCandidateFromKinds(
    kinds: readonly ConcreteFavoriteKind[],
    pools: FavoritePools,
): FavoriteCandidate | undefined {
    const availableKinds = kinds.filter(
        candidateKind => pools.candidates[candidateKind].length > 0,
    );
    if (availableKinds.length === 0) return undefined;

    if (settings.store.mixMode === "balanced") {
        const selectedKind = settings.store.avoidRepeats
            ? kindPicker.take(availableKinds, getRepeatStrength())
            : pickUniform(availableKinds);

        return selectedKind ? pickFromKind(selectedKind, pools) : undefined;
    }

    const allCandidates = availableKinds.flatMap(
        candidateKind => pools.candidates[candidateKind],
    );

    return settings.store.avoidRepeats
        ? candidatePicker.take(allCandidates, getRepeatStrength())
        : pickUniform(allCandidates);
}

function pickCandidate(
    kind: FavoriteKind,
    pools: FavoritePools,
): FavoriteCandidate | undefined {
    return kind === "all"
        ? pickCandidateFromKinds(concreteKinds, pools)
        : pickFromKind(kind, pools);
}

function noCandidateMessage(kind: FavoriteKind, pools: FavoritePools) {
    const requestedKinds = kind === "all" ? concreteKinds : [kind];
    const collectionErrors = requestedKinds
        .map(requestedKind => pools.collectionErrors[requestedKind])
        .filter((error): error is string => error != null);
    if (collectionErrors.length > 0)
        return Array.from(new Set(collectionErrors)).join("\n");

    const rawCount = requestedKinds.reduce(
        (total, requestedKind) => total + pools.rawCounts[requestedKind],
        0,
    );

    if (rawCount === 0) {
        if (kind === "soundboard")
            return SoundboardStore.isFetchingAnySounds()
                ? soundboardStoreLoadingError()
                : soundboardUnavailableError();

        return localize(
            `No ${selectedPoolLabel(kind)} were found. Add some favorites in Discord's expression picker or change the pool settings.`,
            `Aucun ${selectedPoolLabel(kind)} trouvé. Ajoute des favoris dans le sélecteur d'expressions de Discord ou modifie les listes dans les réglages.`,
        );
    }

    return localize(
        `${rawCount} ${selectedPoolLabel(kind)} were detected, but none can be used in this channel. Check server permissions, Nitro access, or deleted favorites.`,
        `${rawCount} ${selectedPoolLabel(kind)} détecté(s), mais aucun n'est utilisable dans ce salon. Vérifie les permissions du serveur, l'accès Nitro ou les favoris supprimés.`,
    );
}

function noCandidateMessageForKinds(
    kinds: readonly ConcreteFavoriteKind[],
    pools: FavoritePools,
) {
    const collectionErrors = kinds
        .map(kind => pools.collectionErrors[kind])
        .filter((error): error is string => error != null);
    if (collectionErrors.length > 0)
        return Array.from(new Set(collectionErrors)).join("\n");

    const rawCount = kinds.reduce(
        (total, kind) => total + pools.rawCounts[kind],
        0,
    );
    const selection = selectedKindsLabel(kinds);

    if (rawCount === 0) {
        if (kinds.length === 1 && kinds[0] === "soundboard") {
            return SoundboardStore.isFetchingAnySounds()
                ? soundboardStoreLoadingError()
                : soundboardUnavailableError();
        }

        return localize(
            `No items were found for the selected types (${selection}). Add some favorites in Discord's expression picker or change the pool settings.`,
            `Aucun élément trouvé pour les types cochés (${selection}). Ajoute des favoris dans le sélecteur d'expressions de Discord ou modifie les listes dans les réglages.`,
        );
    }

    return localize(
        `${rawCount} items were detected for the selected types (${selection}), but none can be used in this channel. Check server permissions, Nitro access, or deleted favorites.`,
        `${rawCount} élément(s) détecté(s) pour les types cochés (${selection}), mais aucun n'est utilisable dans ce salon. Vérifie les permissions du serveur, l'accès Nitro ou les favoris supprimés.`,
    );
}

export function drawRandomFavorite(
    kind: FavoriteKind,
    channel: Channel,
): FavoriteDrawResult {
    const pools = collectFavoritePools(kind, channel);
    const candidate = pickCandidate(kind, pools);
    return candidate
        ? { candidates: [candidate], errors: [] }
        : { candidates: [], errors: [noCandidateMessage(kind, pools)] };
}

export function drawSelectedFavorites(
    kinds: readonly ConcreteFavoriteKind[],
    sendEachSelectedType: boolean,
    channel: Channel,
): FavoriteDrawResult {
    if (kinds.length === 0) {
        return {
            candidates: [],
            errors: [localize(
                "Select at least one type with a right click first.",
                "Sélectionne d'abord au moins un type avec un clic droit.",
            )],
        };
    }

    const pools = collectFavoritePools("all", channel);
    const plan = buildSelectionPlan(
        kinds,
        sendEachSelectedType,
        kind => pickFromKind(kind, pools),
        selectedKinds => pickCandidateFromKinds(selectedKinds, pools),
    );
    const errors = plan.missingKinds.map(kind => noCandidateMessage(kind, pools));

    if (!sendEachSelectedType && plan.candidates.length === 0)
        errors.push(noCandidateMessageForKinds(kinds, pools));

    return { candidates: plan.candidates, errors };
}

export function resetFavoriteSelection() {
    candidatePicker.clear();
    kindPicker.clear();
}
