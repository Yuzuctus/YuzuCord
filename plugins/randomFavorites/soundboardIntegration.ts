/*
 * Vencord, a Discord client mod
 * Copyright (c) 2026 Vendicated and contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import { Logger } from "@utils/Logger";
import type { Channel, SoundboardSound } from "@vencord/discord-types";
import { findByCodeLazy } from "@webpack";
import {
    ChannelStore,
    GuildStore,
    IconUtils,
    PermissionsBits,
    PermissionStore,
    SelectedChannelStore,
    SelectedGuildStore,
    showToast,
    SoundboardStore,
    Toasts,
    UserStore,
} from "@webpack/common";

import {
    createSoundboardSnapshot,
    type SoundboardSnapshot,
} from "./_shared/soundboard/src/attachment";
import {
    canSendSoundboardAttachment,
    ensureSoundboardData,
    resolveSoundboardAudioUrl,
} from "./_shared/soundboard/src/runtime";
import { AdaptiveRandomPicker } from "./adaptiveRandom";
import { createRandomSoundboardGridItems } from "./expressionPicker";
import { localize } from "./localization";
import { getRepeatStrength, settings } from "./settings";
import {
    collectChatSoundboardPool,
    collectUsableSoundboardSounds,
    getRandomSoundboardGuildIconUrl,
    insertRandomSoundboardCategory,
    pickVirtualSoundboardGuildId,
    RANDOM_SOUNDBOARD_CATEGORY_KEY,
    RANDOM_SOUNDBOARD_GUILD_ICON_HASH,
    revokeRandomSoundboardGuildIconUrl,
    SOUNDBOARD_GUILD_CATEGORY_TYPE,
    soundboardCandidateKey,
    type SoundboardCategory,
} from "./soundboardPool";
import type {
    ChatSoundboardCollection,
    FavoriteCandidate,
    SoundboardDrawResult,
    SoundboardSendPreparation,
} from "./types";
import { pickUniform } from "./uniformRandom";

type CanUseSoundboardSound = (
    user: unknown,
    sound: SoundboardSound,
    channel: Channel,
    requireAvailable?: boolean,
) => boolean;

type SendSoundboardSound = (
    sound: SoundboardSound,
    channelId: string,
    analyticsLocations: unknown[],
    sequenceNumber?: number,
) => void;

type SoundboardGuild = NonNullable<
    NonNullable<SoundboardCategory["categoryInfo"]>["guild"]
>;

const logger = new Logger("RandomFavorites");
const canUseSoundboardSound = findByCodeLazy(
    ".canUseSoundboardEverywhere(",
    ".guildId===",
    ".available",
) as CanUseSoundboardSound;
const sendSoundboardSound = findByCodeLazy(
    "SOUNDBOARD_TRACK_USAGE",
    "source_guild_id",
    "SEND_SOUNDBOARD_SOUND",
) as SendSoundboardSound;
const soundboardPicker = new AdaptiveRandomPicker<SoundboardSound>(soundboardCandidateKey);

/** Stable for the whole plugin session; never reuses a real guild id. */
let virtualSoundboardGuildId: string | undefined;
let originalGuildIconUrl: typeof IconUtils.getGuildIconURL | undefined;
let randomGuildIconUrlOverride: typeof IconUtils.getGuildIconURL | undefined;

function getConnectedVoiceChannel(): Channel | undefined {
    const channelId = SelectedChannelStore.getVoiceChannelId();
    return channelId ? ChannelStore.getChannel(channelId) : undefined;
}

function soundboardChannelError(channel?: Channel): string | undefined {
    if (!channel) {
        return localize(
            "Join a voice channel before using the random soundboard.",
            "Rejoins un salon vocal avant d'utiliser le soundboard aléatoire.",
        );
    }

    if (channel.isPrivate()) return;

    if (!channel.isGuildVoiceOrThread()) {
        return localize(
            "The current voice channel does not support the soundboard.",
            "Le salon vocal actuel ne prend pas en charge le soundboard.",
        );
    }

    if (
        !PermissionStore.can(PermissionsBits.SPEAK, channel)
        || !PermissionStore.can(PermissionsBits.USE_SOUNDBOARD, channel)
    ) {
        return localize(
            "You do not have permission to use the soundboard in this voice channel.",
            "Tu n'as pas la permission d'utiliser le soundboard dans ce salon vocal.",
        );
    }
}

function collectSoundboardCandidates(channel: Channel) {
    const user = UserStore.getCurrentUser();
    if (!user) return [];

    return collectUsableSoundboardSounds(
        SoundboardStore.getSounds().values(),
        sound => sound.available !== false
            && canUseSoundboardSound(user, sound, channel, true),
    );
}

export function soundboardStoreLoadingError() {
    return localize(
        "Discord is still loading the accessible soundboard sounds. Try again in a moment.",
        "Discord charge encore les sons Soundboard accessibles. Réessaie dans un instant.",
    );
}

export function soundboardStoreFetchError() {
    return localize(
        "Discord could not load the accessible soundboard sounds. Check your connection, then try again.",
        "Discord n'a pas pu charger les sons Soundboard accessibles. Vérifie ta connexion, puis réessaie.",
    );
}

export function soundboardAttachmentPermissionError() {
    return localize(
        "Soundboard audio cannot be sent in this channel because you need permission to send messages and attach files.",
        "L'audio du soundboard ne peut pas être envoyé dans ce salon : il faut pouvoir envoyer des messages et joindre des fichiers.",
    );
}

export function soundboardUnavailableError() {
    return localize(
        "No accessible soundboard sounds are available for this account.",
        "Aucun son Soundboard accessible n'est disponible pour ce compte.",
    );
}

export async function ensureChatSoundboardData(shouldLoad: boolean) {
    if (!shouldLoad) return;

    await ensureSoundboardData({
        localize,
        logger,
        onStarted: () => showToast(
            localize(
                "Loading accessible Soundboard sounds…",
                "Chargement des sons Soundboard accessibles…",
            ),
            Toasts.Type.MESSAGE,
        ),
    });
}

export function resolveSoundboardPreviewUrl(
    sound: Pick<SoundboardSnapshot, "soundId">,
) {
    return resolveSoundboardAudioUrl(sound.soundId);
}

function createChatSoundboardCandidate(sound: SoundboardSound): FavoriteCandidate {
    const snapshot = createSoundboardSnapshot(sound);
    const key = soundboardCandidateKey(snapshot);

    return {
        kind: "soundboard",
        key,
        label: snapshot.name,
        previewType: "audio",
        previewUrl: resolveSoundboardPreviewUrl(snapshot),
        soundboard: snapshot,
    };
}

/** Collects only store-backed sounds for chat attachments, not vocal playback. */
export function collectChatSoundboardCandidates(
    channel: Channel,
): ChatSoundboardCollection {
    let soundGroups: Iterable<readonly SoundboardSound[]>;

    try {
        soundGroups = SoundboardStore.getSounds().values();
    } catch (error) {
        logger.error("Failed to read Discord's loaded soundboard sounds", error);
        return {
            candidates: [],
            error: soundboardStoreLoadingError(),
            rawCount: 0,
        };
    }

    const canAttach = canSendSoundboardAttachment(channel);
    const pool = collectChatSoundboardPool(soundGroups, canAttach);

    if (!canAttach) {
        return {
            candidates: [],
            error: soundboardAttachmentPermissionError(),
            rawCount: pool.rawCount,
        };
    }

    return {
        candidates: pool.candidates.map(createChatSoundboardCandidate),
        error: pool.rawCount === 0
            ? SoundboardStore.isFetchingAnySounds()
                ? soundboardStoreLoadingError()
                : soundboardUnavailableError()
            : undefined,
        rawCount: pool.rawCount,
    };
}

export function drawRandomSoundboard(): SoundboardDrawResult {
    const channel = getConnectedVoiceChannel();
    const channelError = soundboardChannelError(channel);
    if (channelError || !channel)
        return { error: channelError };

    let sounds: SoundboardSound[];
    try {
        sounds = collectSoundboardCandidates(channel);
    } catch (error) {
        logger.error("Failed to resolve Discord's soundboard sounds", error);
        return {
            error: localize(
                "Discord's soundboard data could not be read. Close and reopen the soundboard, then try again.",
                "Les données du soundboard Discord sont illisibles. Ferme et rouvre le soundboard, puis réessaie.",
            ),
        };
    }

    if (sounds.length === 0) {
        return {
            error: SoundboardStore.isFetchingAnySounds()
                ? localize(
                    "Discord is still loading the soundboard. Try again in a moment.",
                    "Discord charge encore le soundboard. Réessaie dans un instant.",
                )
                : localize(
                    "No soundboard sound is currently usable in this voice channel.",
                    "Aucun son du soundboard n'est actuellement utilisable dans ce salon vocal.",
                ),
        };
    }

    const sound = settings.store.avoidRepeats
        ? soundboardPicker.take(sounds, getRepeatStrength())
        : pickUniform(sounds);

    return sound
        ? { sound }
        : {
            error: localize(
                "No random sound could be selected.",
                "Aucun son aléatoire n'a pu être sélectionné.",
            ),
        };
}

function prepareSoundboardSend(sound: SoundboardSound): SoundboardSendPreparation {
    const channel = getConnectedVoiceChannel();
    const channelError = soundboardChannelError(channel);
    if (channelError || !channel)
        return { error: channelError };

    try {
        const currentSound = SoundboardStore.getSound(sound.guildId, sound.soundId);
        const user = UserStore.getCurrentUser();
        const isStillUsable = currentSound != null
            && user != null
            && canUseSoundboardSound(user, currentSound, channel, true);

        return isStillUsable
            ? { channel, sound: currentSound }
            : {
                error: localize(
                    "This sound is no longer usable. Draw another one before confirming.",
                    "Ce son n'est plus utilisable. Relance le tirage avant de confirmer.",
                ),
            };
    } catch (error) {
        logger.error("Failed to revalidate a soundboard sound", error);
        return {
            error: localize(
                "Discord could not validate this soundboard sound.",
                "Discord n'a pas pu valider ce son du soundboard.",
            ),
        };
    }
}

export function playSoundboardSelection(sound: SoundboardSound) {
    const prepared = prepareSoundboardSend(sound);
    if (prepared.error || !prepared.channel || !prepared.sound) {
        showToast(prepared.error ?? localize(
            "Discord could not validate this soundboard sound.",
            "Discord n'a pas pu valider ce son du soundboard.",
        ), Toasts.Type.FAILURE);
        return false;
    }

    try {
        sendSoundboardSound(prepared.sound, prepared.channel.id, []);
        return true;
    } catch (error) {
        logger.error("Discord refused to play a random soundboard sound", error);
        showToast(localize(
            "Discord could not play this sound in the voice channel.",
            "Discord n'a pas pu jouer ce son dans le salon vocal.",
        ), Toasts.Type.FAILURE);
        return false;
    }
}

function soundboardInsertionGuildId() {
    const voiceChannel = getConnectedVoiceChannel();
    return voiceChannel
        ? voiceChannel.guild_id
        : SelectedGuildStore.getGuildId() ?? undefined;
}

function installRandomSoundboardGuildIconOverride() {
    if (originalGuildIconUrl) return;

    originalGuildIconUrl = IconUtils.getGuildIconURL;
    randomGuildIconUrlOverride = data => {
        if (virtualSoundboardGuildId && data.id === virtualSoundboardGuildId)
            return getRandomSoundboardGuildIconUrl();

        return originalGuildIconUrl!(data);
    };
    IconUtils.getGuildIconURL = randomGuildIconUrlOverride;
}

function restoreRandomSoundboardGuildIconOverride() {
    if (!originalGuildIconUrl) return;

    if (IconUtils.getGuildIconURL === randomGuildIconUrlOverride)
        IconUtils.getGuildIconURL = originalGuildIconUrl;

    originalGuildIconUrl = undefined;
    randomGuildIconUrlOverride = undefined;
}

function resolveVirtualSoundboardGuildId() {
    if (
        virtualSoundboardGuildId
        && GuildStore.getGuild(virtualSoundboardGuildId) == null
    ) {
        return virtualSoundboardGuildId;
    }

    virtualSoundboardGuildId = pickVirtualSoundboardGuildId(
        [UserStore.getCurrentUser()?.id],
        id => GuildStore.getGuild(id) != null,
    );
    return virtualSoundboardGuildId;
}

function createRandomSoundboardGuild(
    baseGuild: SoundboardGuild | undefined,
    virtualGuildId: string,
): SoundboardGuild {
    const virtualGuild = Object.create(baseGuild ?? null) as SoundboardGuild;
    const iconUrl = getRandomSoundboardGuildIconUrl();

    Object.defineProperties(virtualGuild, {
        id: { value: virtualGuildId, enumerable: true },
        name: { value: "FavoriteRandom", enumerable: true },
        acronym: { value: "FR", enumerable: true },
        icon: { value: RANDOM_SOUNDBOARD_GUILD_ICON_HASH, enumerable: true },
        iconHash: { value: RANDOM_SOUNDBOARD_GUILD_ICON_HASH, enumerable: true },
        getAcronym: { value: () => "FR" },
        getIconURL: { value: () => iconUrl },
    });

    return virtualGuild;
}

export function addRandomSoundboardCategory(
    categories: readonly SoundboardCategory[],
): readonly SoundboardCategory[] {
    // A private call has no guild id; use a native guild only as a prototype.
    const currentGuildId = soundboardInsertionGuildId();

    const guildCategory = (currentGuildId
        ? categories.find(category => category.categoryInfo?.guild?.id === currentGuildId)
        : undefined)
        ?? categories.find(category => category.categoryInfo?.guild != null);
    const categoryType = guildCategory?.categoryInfo?.type ?? SOUNDBOARD_GUILD_CATEGORY_TYPE;
    const baseGuild = (currentGuildId ? GuildStore.getGuild(currentGuildId) : undefined)
        ?? guildCategory?.categoryInfo?.guild;
    const fallbackGuild = baseGuild ?? GuildStore.getGuildsArray()[0];

    const virtualGuildId = resolveVirtualSoundboardGuildId();

    return insertRandomSoundboardCategory(
        categories,
        {
            key: RANDOM_SOUNDBOARD_CATEGORY_KEY,
            categoryInfo: {
                type: categoryType,
                guild: createRandomSoundboardGuild(fallbackGuild, virtualGuildId),
                isNitroLocked: false,
            },
            items: createRandomSoundboardGridItems(virtualGuildId),
        },
        currentGuildId,
    );
}

export function startRandomSoundboardIntegration() {
    installRandomSoundboardGuildIconOverride();
}

export function stopRandomSoundboardIntegration() {
    restoreRandomSoundboardGuildIconOverride();
    soundboardPicker.clear();
    virtualSoundboardGuildId = undefined;
    revokeRandomSoundboardGuildIconUrl();
}
