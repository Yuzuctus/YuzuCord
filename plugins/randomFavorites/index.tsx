/*
 * Vencord, a Discord client mod
 * Copyright (c) 2026 Vendicated and contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import "./styles.css";

import { ChatBarButton, ChatBarButtonFactory } from "@api/ChatButtons";
import {
    ApplicationCommandInputType,
    ApplicationCommandOptionType,
    findOption,
    sendBotMessage,
} from "@api/Commands";
import { sendMessage } from "@utils/discord";
import { Logger } from "@utils/Logger";
import definePlugin from "@utils/types";
import {
    Channel,
    Command,
    Emoji,
    RenderModalProps,
    SoundboardSound,
} from "@vencord/discord-types";
import { findByPropsLazy } from "@webpack";
import {
    ChannelStore,
    ContextMenuApi,
    EmojiStore,
    ExpressionPickerStore,
    FluxDispatcher,
    Menu,
    MessageActions,
    Modal,
    openModal,
    Parser,
    PendingReplyStore,
    SelectedChannelStore,
    showToast,
    SoundboardStore,
    Toasts,
    useState,
} from "@webpack/common";

import {
    shouldLoadChatSoundboardForKind,
    shouldLoadChatSoundboardForKinds,
} from "./_shared/soundboard/src/loader";
import {
    sendSoundboardAttachment,
    SoundboardAttachmentError,
} from "./_shared/soundboard/src/runtime";
import { AdaptiveRandomPicker } from "./adaptiveRandom";
import {
    addRandomEmojiCategory,
    addRandomEmojiGridCategoryIds,
    addRandomStickerCategory,
    getActiveExpressionPickerView,
    getRandomEmojiCategoryItems,
    getRandomEmojiCategoryLabel,
    getRandomEmojiPickerActionClass,
    getRandomPickerButtonLabel,
    getRandomPickerCategoryLabel,
    isRandomEmojiCategoryId,
    isRandomSoundboardActionSound,
    isRandomStickerCategory,
    type NativeEmojiSelect,
    type NativeEmojiSelection,
    type RandomPickerEmoji,
    type RandomSoundboardAction,
    type RandomStickerGridItem,
    REACTION_EMOJI_INTENTION,
    renderRandomEmojiPickerActionContent,
    resetExpressionPickerCaches,
    transformRandomStickerGrid,
} from "./expressionPicker";
import { FavoritePreviewCard } from "./favoritePreview";
import {
    canAttachFiles,
    canSendMessages,
    collectFavoritePools,
    drawRandomFavorite,
    drawSelectedFavorites,
    formatEmoji,
    isUsableEmoji,
    kindLabel,
    resetFavoriteSelection,
    selectedKindsLabel,
    selectedLeftClickKinds,
    shortKindLabel,
} from "./favoriteSelection";
import { RandomFavoritesIcon, renderRandomPickerIcon } from "./icons";
import { localize } from "./localization";
import { formatGifContent } from "./messageFormatting";
import {
    emojiActionButtonClassPatch,
    emojiActionButtonClassReplacement,
    emojiActionButtonContentPatch,
    emojiActionButtonContentReplacement,
    emojiCategoryIconPatch,
    emojiCategoryIconReplacement,
    emojiCategoryItemsPatch,
    emojiCategoryItemsReplacement,
    emojiCategoryLabelPatch,
    emojiCategoryLabelReplacement,
    emojiCategoryPatch,
    emojiCategoryReplacement,
    emojiGridCategoriesPatch,
    emojiGridCategoriesReplacement,
    emojiPickerModuleFind,
    emojiSelectionPatch,
    emojiSelectionReplacement,
    soundboardActionSelectionPatch,
    soundboardActionSelectionReplacement,
    stickerButtonLabelPatch,
    stickerButtonLabelReplacement,
    stickerCategoryRailPatch,
    stickerCategoryRailReplacement,
    stickerGridCategoriesPatch,
    stickerGridCategoriesReplacement,
    stickerGridModuleFind,
    stickerGridResultPatch,
    stickerGridResultReplacement,
    stickerKeyboardSelectionPatch,
    stickerKeyboardSelectionReplacement,
    stickerMouseSelectionPatch,
    stickerMouseSelectionReplacement,
    stickerRailCategoriesPatch,
    stickerRailCategoriesReplacement,
} from "./pickerPatches";
import { buildReactionEmojiPool, reactionEmojiKey } from "./reactionPool";
import { getRepeatStrength, settings } from "./settings";
import {
    addRandomSoundboardCategory,
    ensureChatSoundboardData,
    soundboardAttachmentPermissionError,
    soundboardStoreFetchError,
    startRandomSoundboardIntegration,
    stopRandomSoundboardIntegration,
} from "./soundboardIntegration";
import { runRandomSoundboard } from "./soundboardPreview";
import type {
    ConcreteFavoriteKind,
    FavoriteCandidate,
    FavoriteDrawResult,
    FavoriteKind,
    SelectedSendResult,
    SendResult,
} from "./types";
import { pickUniform } from "./uniformRandom";

interface EmojiAvailabilityManager {
    isEmojiFiltered(options: {
        channel: Channel;
        emoji: Emoji;
        intention: number;
    }): boolean;
}

const logger = new Logger("RandomFavorites");
const EmojiAvailability = findByPropsLazy(
    "isEmojiFiltered",
    "getEmojiUnavailableReason",
) as EmojiAvailabilityManager;
const activeChannels = new Set<string>();
const reactionPicker = new AdaptiveRandomPicker<Emoji>(reactionEmojiKey);

function buildReplyOptions(channelId: string) {
    return MessageActions.getSendMessageOptionsForReply(
        PendingReplyStore.getPendingReply(channelId),
    ) ?? {};
}

async function sendSoundboardCandidate(candidate: FavoriteCandidate, channel: Channel) {
    const snapshot = candidate.soundboard;
    if (!snapshot) {
        throw new SoundboardAttachmentError(
            "stale",
            localize(
                "This Soundboard candidate is incomplete. Draw another sound before sending.",
                "Ce candidat Soundboard est incomplet. Relance le tirage avant l'envoi.",
            ),
        );
    }

    await sendSoundboardAttachment(snapshot, channel, {
        fileName: settings.store.soundboardFileName,
        localize,
        logger,
    });
}

async function sendCandidate(candidate: FavoriteCandidate, channel: Channel) {
    if (candidate.kind === "soundboard") {
        await sendSoundboardCandidate(candidate, channel);
        return;
    }

    const options = buildReplyOptions(channel.id);
    const rawContent = candidate.content ?? "";
    const content = candidate.kind === "gif"
        ? formatGifContent(rawContent, {
            label: settings.store.gifLabel,
            maskWithSpoiler: settings.store.maskGifs,
            showLabel: settings.store.showGifLabel,
        })
        : rawContent;

    if (candidate.stickerId)
        options.stickerIds = [candidate.stickerId];

    await sendMessage(
        channel.id,
        { content },
        false,
        options,
    );

    FluxDispatcher.dispatch({
        type: "DELETE_PENDING_REPLY",
        channelId: channel.id,
    });
}

async function sendPreparedFavorites(
    candidates: readonly FavoriteCandidate[],
    channel: Channel,
): Promise<SelectedSendResult> {
    if (activeChannels.has(channel.id)) {
        return {
            sentCount: 0,
            errors: [localize(
                "Random items are already being sent in this channel.",
                "Des éléments aléatoires sont déjà en cours d'envoi dans ce salon.",
            )],
        };
    }

    if (!canSendMessages(channel)) {
        return {
            sentCount: 0,
            errors: [localize(
                "You do not have permission to send messages in this channel.",
                "Tu n'as pas la permission d'envoyer des messages dans ce salon.",
            )],
        };
    }

    activeChannels.add(channel.id);

    try {
        let sentCount = 0;
        const errors: string[] = [];

        for (const candidate of candidates) {
            try {
                await sendCandidate(candidate, channel);
                sentCount++;
            } catch (error) {
                logger.error(
                    `Failed to send a random ${candidate.kind} from the selected batch`,
                    error,
                );
                errors.push(error instanceof SoundboardAttachmentError
                    ? error.message
                    : localize(
                        `Discord refused to send the random ${shortKindLabel(candidate.kind)}. It may have been deleted or become unavailable.`,
                        `Discord a refusé d'envoyer ${shortKindLabel(candidate.kind) === "emote" ? "l'emote" : `le ${shortKindLabel(candidate.kind)}`} aléatoire. L'élément a peut-être été supprimé ou n'est plus disponible.`,
                    ));
            }
        }

        return { sentCount, errors };
    } finally {
        activeChannels.delete(channel.id);
    }
}

async function sendRandomFavorite(
    kind: FavoriteKind,
    channel: Channel,
): Promise<SendResult> {
    const draw = drawRandomFavorite(kind, channel);
    if (draw.candidates.length === 0)
        return { ok: false, message: draw.errors[0] };

    const result = await sendPreparedFavorites(draw.candidates, channel);
    return result.sentCount > 0
        ? { ok: true, candidate: draw.candidates[0] }
        : { ok: false, message: result.errors[0] };
}

async function sendSelectedFavorites(
    kinds: readonly ConcreteFavoriteKind[],
    sendEachSelectedType: boolean,
    channel: Channel,
): Promise<SelectedSendResult> {
    const draw = drawSelectedFavorites(kinds, sendEachSelectedType, channel);
    if (draw.candidates.length === 0)
        return { sentCount: 0, errors: draw.errors };

    const result = await sendPreparedFavorites(draw.candidates, channel);
    return {
        sentCount: result.sentCount,
        errors: [...draw.errors, ...result.errors],
    };
}

function showDrawErrors(errors: readonly string[]) {
    if (errors.length > 0)
        showToast(errors.join("\n"), Toasts.Type.FAILURE);
}

function RandomFavoritesPreviewModal({
    channel,
    drawAgain,
    initialDraw,
    modalProps,
}: {
    channel: Channel;
    drawAgain: () => FavoriteDrawResult;
    initialDraw: FavoriteDrawResult;
    modalProps: RenderModalProps;
}) {
    const [candidates, setCandidates] = useState(initialDraw.candidates);
    const [isSending, setIsSending] = useState(false);

    function reroll() {
        const draw = drawAgain();
        showDrawErrors(draw.errors);
        if (draw.candidates.length > 0)
            setCandidates(draw.candidates);
    }

    async function confirmSend() {
        setIsSending(true);
        try {
            const result = await sendPreparedFavorites(candidates, channel);
            showDrawErrors(result.errors);
            if (result.sentCount > 0)
                modalProps.onClose();
        } finally {
            setIsSending(false);
        }
    }

    return (
        <Modal
            {...modalProps}
            title={localize("Safe random preview", "Aperçu aléatoire sécurisé")}
            subtitle={localize(
                "Nothing will be sent until you confirm this selection.",
                "Rien ne sera envoyé avant ta confirmation.",
            )}
            actions={[
                {
                    text: localize("Cancel", "Annuler"),
                    variant: "secondary",
                    disabled: isSending,
                    onClick: modalProps.onClose,
                },
                {
                    text: localize("Draw again", "Relancer"),
                    variant: "secondary",
                    disabled: isSending,
                    onClick: reroll,
                },
                {
                    text: isSending
                        ? localize("Sending…", "Envoi…")
                        : localize(
                            candidates.length > 1 ? `Send ${candidates.length} items` : "Send",
                            candidates.length > 1 ? `Envoyer les ${candidates.length} éléments` : "Envoyer",
                        ),
                    variant: "primary",
                    disabled: isSending || candidates.length === 0,
                    onClick: () => void confirmSend(),
                },
            ]}
        >
            <div
                className={`vc-rf-preview-grid${candidates.length === 1 ? " vc-rf-preview-grid-single" : ""}`}
            >
                {candidates.map(candidate => (
                    <FavoritePreviewCard candidate={candidate} key={candidate.key} />
                ))}
            </div>
            <p className="vc-rf-preview-hint">
                {localize(
                    "Draw again changes the private selection without posting anything.",
                    "Relancer change uniquement l'aperçu privé, sans rien publier.",
                )}
            </p>
        </Modal>
    );
}

function openFavoritePreview(channel: Channel, drawAgain: () => FavoriteDrawResult) {
    if (!canSendMessages(channel)) {
        showDrawErrors([localize(
            "You do not have permission to send messages in this channel.",
            "Tu n'as pas la permission d'envoyer des messages dans ce salon.",
        )]);
        return;
    }

    const initialDraw = drawAgain();
    showDrawErrors(initialDraw.errors);
    if (initialDraw.candidates.length === 0) return;

    openModal(modalProps => (
        <RandomFavoritesPreviewModal
            channel={channel}
            drawAgain={drawAgain}
            initialDraw={initialDraw}
            modalProps={modalProps}
        />
    ));
}

function RandomReactionPreviewModal({
    channel,
    initialEmoji,
    modalProps,
    nativeSelect,
    originalSelection,
}: {
    channel: Channel;
    initialEmoji: Emoji;
    modalProps: RenderModalProps;
    nativeSelect: NativeEmojiSelect;
    originalSelection: NativeEmojiSelection;
}) {
    const [emoji, setEmoji] = useState(initialEmoji);

    function reroll() {
        const nextEmoji = drawRandomReactionEmoji(channel);
        if (!nextEmoji) {
            showToast(reactionUnavailableError(), Toasts.Type.FAILURE);
            return;
        }

        setEmoji(nextEmoji);
    }

    function confirmReaction() {
        if (applyNativeReactionSelection(nativeSelect, originalSelection, emoji))
            modalProps.onClose();
    }

    return (
        <Modal
            {...modalProps}
            title={localize(
                "Safe random reaction preview",
                "Aperçu sécurisé de la réaction",
            )}
            subtitle={localize(
                "No reaction will be added until you confirm.",
                "Aucune réaction ne sera ajoutée avant ta confirmation.",
            )}
            actions={[
                {
                    text: localize("Cancel", "Annuler"),
                    variant: "secondary",
                    onClick: modalProps.onClose,
                },
                {
                    text: localize("Draw again", "Relancer"),
                    variant: "secondary",
                    onClick: reroll,
                },
                {
                    text: localize("React", "Réagir"),
                    variant: "primary",
                    onClick: confirmReaction,
                },
            ]}
        >
            <div className="vc-rf-reaction-preview">
                <div
                    className="vc-rf-reaction-preview-emoji"
                    role="img"
                    aria-label={emoji.name}
                >
                    {Parser.parse(formatEmoji(emoji))}
                </div>
                <strong>{localize("Random reaction", "Réaction aléatoire")}</strong>
                <span>{emoji.name}</span>
            </div>
            <p className="vc-rf-preview-hint">
                {localize(
                    "Draw again changes only this private preview.",
                    "Relancer change uniquement cet aperçu privé.",
                )}
            </p>
        </Modal>
    );
}

function openRandomReactionPreview(
    channel: Channel,
    nativeSelect: NativeEmojiSelect,
    originalSelection: NativeEmojiSelection,
    initialEmoji: Emoji,
) {
    openModal(modalProps => (
        <RandomReactionPreviewModal
            channel={channel}
            initialEmoji={initialEmoji}
            modalProps={modalProps}
            nativeSelect={nativeSelect}
            originalSelection={originalSelection}
        />
    ));
}

async function runRandomSoundboardChat(action: RandomSoundboardAction) {
    const channelId = SelectedChannelStore.getChannelId();
    const channel = channelId ? ChannelStore.getChannel(channelId) : undefined;
    if (!channel) {
        showToast(localize(
            "Open a text channel before using FavoriteRandom.",
            "Ouvre un salon textuel avant d'utiliser FavoriteRandom.",
        ), Toasts.Type.FAILURE);
        return;
    }

    try {
        await ensureChatSoundboardData(!SoundboardStore.hasFetchedAllSounds());
    } catch (error) {
        showToast(
            error instanceof Error ? error.message : soundboardStoreFetchError(),
            Toasts.Type.FAILURE,
        );
        return;
    }

    ExpressionPickerStore.closeExpressionPicker();
    const draw = () => drawRandomFavorite("soundboard", channel);
    if (action === "preview") {
        openFavoritePreview(channel, draw);
        return;
    }

    const result = await sendRandomFavorite("soundboard", channel);
    if (!result.ok)
        showToast(result.message, Toasts.Type.FAILURE);
}

async function runPickerFavoriteKind(kind: "emoji" | "sticker") {
    const channelId = SelectedChannelStore.getChannelId();
    const channel = channelId ? ChannelStore.getChannel(channelId) : undefined;
    if (!channel) {
        showToast(localize(
            "Open a text channel before using FavoriteRandom.",
            "Ouvre un salon textuel avant d'utiliser FavoriteRandom.",
        ), Toasts.Type.FAILURE);
        return;
    }

    ExpressionPickerStore.closeExpressionPicker();
    if (settings.store.previewBeforeSend) {
        openFavoritePreview(channel, () => drawRandomFavorite(kind, channel));
        return;
    }

    const result = await sendRandomFavorite(kind, channel);
    if (!result.ok)
        showToast(result.message, Toasts.Type.FAILURE);
}

function handleRandomSoundboardSelection(sound?: SoundboardSound | null) {
    if (!isRandomSoundboardActionSound(sound)) return false;

    if (getActiveExpressionPickerView() === "soundboard")
        void runRandomSoundboardChat(sound.randomFavoritesAction);
    else
        runRandomSoundboard(sound.randomFavoritesAction);

    return true;
}

function collectUsableReactionEmojis(channel: Channel): Emoji[] {
    const source = EmojiStore
        .getDisambiguatedEmojiContext(channel.guild_id ?? null)
        .getDisambiguatedEmoji();

    return buildReactionEmojiPool(source, emoji => {
        if (!isUsableEmoji(emoji, channel)) return false;

        try {
            if (EmojiAvailability.isEmojiFiltered({
                channel,
                emoji,
                intention: REACTION_EMOJI_INTENTION,
            })) return false;
        } catch (error) {
            logger.warn("Discord could not validate an emoji for reactions", error);
            return false;
        }

        return true;
    });
}

function drawRandomReactionEmoji(channel: Channel): Emoji | undefined {
    const emojis = collectUsableReactionEmojis(channel);
    if (emojis.length === 0) return;

    return settings.store.avoidRepeats
        ? reactionPicker.take(emojis, getRepeatStrength())
        : pickUniform(emojis);
}

function selectedTextChannel(): Channel | undefined {
    const channelId = SelectedChannelStore.getChannelId();
    return channelId ? ChannelStore.getChannel(channelId) : undefined;
}

function reactionUnavailableError() {
    return localize(
        "No emoji is currently usable as a reaction on this message.",
        "Aucune emote n'est actuellement utilisable en réaction sur ce message.",
    );
}

function applyNativeReactionSelection(
    nativeSelect: NativeEmojiSelect,
    originalSelection: NativeEmojiSelection,
    emoji: Emoji,
) {
    try {
        const result = nativeSelect({
            ...originalSelection,
            emoji: emoji as RandomPickerEmoji,
            isBurst: false,
            willClose: true,
        });

        if (result instanceof Promise) {
            void result.catch(error => {
                logger.error("Discord refused the random reaction", error);
                showToast(localize(
                    "Discord could not add this random reaction.",
                    "Discord n'a pas pu ajouter cette réaction aléatoire.",
                ), Toasts.Type.FAILURE);
            });
        }

        return true;
    } catch (error) {
        logger.error("Discord refused the random reaction", error);
        showToast(localize(
            "Discord could not add this random reaction.",
            "Discord n'a pas pu ajouter cette réaction aléatoire.",
        ), Toasts.Type.FAILURE);
        return false;
    }
}

function handleRandomEmojiSelection(
    nativeSelect: NativeEmojiSelect,
    selection: NativeEmojiSelection,
) {
    const emoji = selection?.emoji;
    if (!emoji?.randomFavoritesKind) return false;

    if (emoji.randomFavoritesKind === "emoji") {
        void runPickerFavoriteKind("emoji");
        return true;
    }

    const channel = selectedTextChannel();
    if (!channel) {
        showToast(localize(
            "The message channel could not be found.",
            "Le salon du message est introuvable.",
        ), Toasts.Type.FAILURE);
        return true;
    }

    const randomEmoji = drawRandomReactionEmoji(channel);
    if (!randomEmoji) {
        showToast(reactionUnavailableError(), Toasts.Type.FAILURE);
        return true;
    }

    if (emoji.randomFavoritesAction === "preview") {
        openRandomReactionPreview(channel, nativeSelect, selection, randomEmoji);
        return true;
    }

    applyNativeReactionSelection(nativeSelect, selection, randomEmoji);
    return true;
}

function handleRandomPickerGridItem(item?: RandomStickerGridItem) {
    if (item?.randomFavoritesKind !== "sticker") return false;

    void runPickerFavoriteKind("sticker");
    return true;
}

async function runFromCommand(kind: FavoriteKind, channel: Channel) {
    try {
        await ensureChatSoundboardData(
            shouldLoadChatSoundboardForKind(kind, SoundboardStore.hasFetchedAllSounds()),
        );
    } catch (error) {
        const message = error instanceof Error ? error.message : soundboardStoreFetchError();
        sendBotMessage(channel.id, { content: `🎲 ${message}` });
        return;
    }

    if (settings.store.previewBeforeSend) {
        openFavoritePreview(channel, () => drawRandomFavorite(kind, channel));
        return;
    }

    const result = await sendRandomFavorite(kind, channel);
    if (!result.ok)
        sendBotMessage(channel.id, { content: `🎲 ${result.message}` });
}

async function runSelectedFromButton(channel: Channel) {
    const kinds = selectedLeftClickKinds(channel);
    const { sendEachSelectedType } = settings.store;

    try {
        await ensureChatSoundboardData(
            shouldLoadChatSoundboardForKinds(kinds, SoundboardStore.hasFetchedAllSounds()),
        );
    } catch (error) {
        showToast(
            error instanceof Error ? error.message : soundboardStoreFetchError(),
            Toasts.Type.FAILURE,
        );
        return;
    }

    const selectionError = settings.store.sendSoundboardsOnLeftClick && !canAttachFiles(channel)
        ? soundboardAttachmentPermissionError()
        : undefined;
    const draw = () => {
        const result = drawSelectedFavorites(kinds, sendEachSelectedType, channel);
        if (selectionError)
            result.errors.unshift(selectionError);
        return result;
    };

    if (settings.store.previewBeforeSend) {
        openFavoritePreview(
            channel,
            draw,
        );
        return;
    }

    const result = await sendSelectedFavorites(
        kinds,
        sendEachSelectedType,
        channel,
    );
    if (selectionError)
        result.errors.unshift(selectionError);
    if (result.errors.length > 0)
        showToast(result.errors.join("\n"), Toasts.Type.FAILURE);
}

function favoriteStats(channel: Channel) {
    const pools = collectFavoritePools("all", channel);
    if (!pools) {
        return localize(
            "Discord has not loaded the synced favorites settings yet.",
            "Discord n'a pas encore chargé les réglages de favoris synchronisés.",
        );
    }

    const line = (kind: ConcreteFavoriteKind, icon: string) =>
        `${icon} ${kindLabel(kind)}: **${pools.candidates[kind].length}** / ${pools.rawCounts[kind]}`;

    return [
        localize(
            "**Random items — usable / detected**",
            "**Éléments aléatoires — utilisables / détectés**",
        ),
        line("gif", "🖼️"),
        line("emoji", "😄"),
        line("sticker", "🏷️"),
        line("soundboard", "🔊"),
    ].join("\n");
}

function RandomFavoritesMenu({ channel }: { channel: Channel; }) {
    const selection = settings.use([
        "previewBeforeSend",
        "sendEachSelectedType",
        "mixMode",
        "sendGifsOnLeftClick",
        "sendEmojisOnLeftClick",
        "sendStickersOnLeftClick",
        "sendSoundboardsOnLeftClick",
    ]);

    return (
        <Menu.Menu
            navId="random-favorites"
            onClose={ContextMenuApi.closeContextMenu}
            aria-label="Random Favorites"
        >
            <Menu.MenuGroup
                label={localize("Left-click mode", "Mode du clic gauche")}
            >
                <Menu.MenuCheckboxItem
                    id="random-favorites-safe-preview"
                    label={localize(
                        "Safe preview before sending",
                        "Aperçu sécurisé avant envoi",
                    )}
                    checked={selection.previewBeforeSend}
                    dontCloseOnAction
                    action={() =>
                        settings.store.previewBeforeSend = !selection.previewBeforeSend
                    }
                />
                <Menu.MenuCheckboxItem
                    id="random-favorites-send-each"
                    label={localize(
                        "One item from each selected type",
                        "Un élément de chaque type coché",
                    )}
                    checked={selection.sendEachSelectedType}
                    dontCloseOnAction
                    action={() =>
                        settings.store.sendEachSelectedType = !selection.sendEachSelectedType
                    }
                />
            </Menu.MenuGroup>
            {!selection.sendEachSelectedType && (
                <>
                    <Menu.MenuSeparator />
                    <Menu.MenuGroup
                        label={localize(
                            "Mixed-mode type distribution",
                            "Répartition des types en mode mixte",
                        )}
                    >
                        <Menu.MenuRadioItem
                            id="random-favorites-mix-balanced"
                            group="random-favorites-mix-mode"
                            label={localize(
                                "Balanced distribution (equal base weight per type)",
                                "Répartition équilibrée (même poids de base par type)",
                            )}
                            checked={selection.mixMode === "balanced"}
                            dontCloseOnAction
                            action={() => settings.store.mixMode = "balanced"}
                        />
                        <Menu.MenuRadioItem
                            id="random-favorites-mix-uniform"
                            group="random-favorites-mix-mode"
                            label={localize(
                                "Fully random (equal chance per item)",
                                "Totalement aléatoire (même chance par élément)",
                            )}
                            checked={selection.mixMode === "uniform"}
                            dontCloseOnAction
                            action={() => settings.store.mixMode = "uniform"}
                        />
                    </Menu.MenuGroup>
                </>
            )}
            <Menu.MenuSeparator />
            <Menu.MenuGroup
                label={localize("Included types", "Types inclus")}
            >
                <Menu.MenuCheckboxItem
                    id="random-favorites-select-gif"
                    label="GIF"
                    checked={selection.sendGifsOnLeftClick}
                    dontCloseOnAction
                    action={() =>
                        settings.store.sendGifsOnLeftClick = !selection.sendGifsOnLeftClick
                    }
                />
                <Menu.MenuCheckboxItem
                    id="random-favorites-select-emoji"
                    label={localize("Emoji", "Emote")}
                    checked={selection.sendEmojisOnLeftClick}
                    dontCloseOnAction
                    action={() =>
                        settings.store.sendEmojisOnLeftClick = !selection.sendEmojisOnLeftClick
                    }
                />
                <Menu.MenuCheckboxItem
                    id="random-favorites-select-sticker"
                    label="Sticker"
                    checked={selection.sendStickersOnLeftClick}
                    dontCloseOnAction
                    action={() =>
                        settings.store.sendStickersOnLeftClick = !selection.sendStickersOnLeftClick
                    }
                />
                <Menu.MenuCheckboxItem
                    id="random-favorites-select-soundboard"
                    label="Soundboard"
                    checked={selection.sendSoundboardsOnLeftClick}
                    disabled={!canAttachFiles(channel)}
                    dontCloseOnAction
                    action={() =>
                        settings.store.sendSoundboardsOnLeftClick = !selection.sendSoundboardsOnLeftClick
                    }
                />
            </Menu.MenuGroup>
            <Menu.MenuSeparator />
            <Menu.MenuItem
                id="random-favorites-stats"
                label={localize("Show favorite counts", "Afficher le nombre de favoris")}
                action={() => sendBotMessage(channel.id, { content: favoriteStats(channel) })}
            />
        </Menu.Menu>
    );
}

const RandomFavoritesButton: ChatBarButtonFactory = ({
    channel,
    disabled,
    isAnyChat,
}) => {
    const pluginSettings = settings.use([
        "showChatBarButton",
        "previewBeforeSend",
        "sendEachSelectedType",
        "mixMode",
        "sendGifsOnLeftClick",
        "sendEmojisOnLeftClick",
        "sendStickersOnLeftClick",
        "sendSoundboardsOnLeftClick",
    ]);

    if (
        !isAnyChat
        || disabled
        || !pluginSettings.showChatBarButton
        || !canSendMessages(channel)
    ) return null;

    const selectedKinds = selectedLeftClickKinds(channel);
    const selectionLabel = selectedKindsLabel(selectedKinds);
    const actionTooltip = pluginSettings.sendEachSelectedType
        ? localize(
            `Send one of each: ${selectionLabel} · Right-click to configure`,
            `Envoyer un de chaque : ${selectionLabel} · Clic droit pour configurer`,
        )
        : pluginSettings.mixMode === "balanced"
            ? localize(
                `Send one (balanced types): ${selectionLabel} · Right-click to configure`,
                `Envoyer un seul (types équilibrés) : ${selectionLabel} · Clic droit pour configurer`,
            )
            : localize(
                `Send one among: ${selectionLabel} · Right-click to configure`,
                `Envoyer un seul parmi : ${selectionLabel} · Clic droit pour configurer`,
            );
    const tooltip = pluginSettings.previewBeforeSend
        ? localize(
            `Preview safely: ${selectionLabel} · Right-click to configure`,
            `Prévisualiser sans risque : ${selectionLabel} · Clic droit pour configurer`,
        )
        : actionTooltip;

    return (
        <ChatBarButton
            tooltip={tooltip}
            onClick={() => void runSelectedFromButton(channel)}
            onContextMenu={event => {
                event.preventDefault();
                ContextMenuApi.openContextMenu(
                    event,
                    () => <RandomFavoritesMenu channel={channel} />,
                );
            }}
        >
            <RandomFavoritesIcon />
        </ChatBarButton>
    );
};

function makeFixedKindCommand(
    name: string,
    description: string,
    kind: ConcreteFavoriteKind,
): Command {
    return {
        name,
        description,
        inputType: ApplicationCommandInputType.BUILT_IN,
        execute: async (_, { channel }) => runFromCommand(kind, channel),
    };
}

const commands: Command[] = [
    {
        name: "random-favorite",
        description: "Send a random item from your Discord favorites",
        inputType: ApplicationCommandInputType.BUILT_IN,
        options: [{
            name: "type",
            description: "Limit the random selection to one favorite type",
            type: ApplicationCommandOptionType.STRING,
            required: false,
            choices: [
                { name: "All favorites", label: "All favorites", value: "all" },
                { name: "GIF", label: "GIF", value: "gif" },
                { name: "Emoji", label: "Emoji", value: "emoji" },
                { name: "Sticker", label: "Sticker", value: "sticker" },
                { name: "Soundboard", label: "Soundboard", value: "soundboard" },
            ],
        }],
        execute: async (args, { channel }) => {
            const kind = findOption<FavoriteKind>(args, "type", "all");
            await runFromCommand(kind, channel);
        },
    },
    makeFixedKindCommand(
        "random-gif",
        "Send a random GIF from your Discord favorites",
        "gif",
    ),
    makeFixedKindCommand(
        "random-emoji",
        "Send a random emoji from your Discord favorites",
        "emoji",
    ),
    makeFixedKindCommand(
        "random-sticker",
        "Send a random sticker from your Discord favorites",
        "sticker",
    ),
    makeFixedKindCommand(
        "random-soundboard",
        "Send a random accessible soundboard sound as an audio attachment",
        "soundboard",
    ),
    {
        name: "random-favorite-stats",
        description: "Show how many saved favorites are currently usable",
        inputType: ApplicationCommandInputType.BUILT_IN,
        execute: (_, { channel }) => {
            sendBotMessage(channel.id, { content: favoriteStats(channel) });
        },
    },
];

export default definePlugin({
    name: "RandomFavorites",
    description: "Send a random favorite GIF, emoji, sticker, soundboard sound, or a balanced mix.",
    authors: [{ name: "Yuzuctus", id: 0n }],
    tags: ["Chat", "Commands", "Emotes", "Fun", "Media"],
    settings,
    commands,

    patches: [
        {
            // This accessibility id belongs to the native Soundboard picker.
            find: "soundboard_guild_",
            replacement: [
                {
                    match: /(\i)=(\i)\.useMemo\(\(\)=>(\i)\.filter\((\i)=>\4\.items\.length>0\),\[\3\]\)/,
                    replace: "$1=$2.useMemo(()=>$self.addRandomSoundboardCategory($3.filter($4=>$4.items.length>0)),[$3])",
                },
                {
                    match: /\(0,(\i)\.jsx\)\((\i),\{soundboardListRef:(\i),categories:(\i),shouldUpsellLockedCategories:/,
                    replace: "(0,$1.jsx)($2,{soundboardListRef:$3,categories:$self.addRandomSoundboardCategory($4),shouldUpsellLockedCategories:",
                },
                {
                    match: soundboardActionSelectionPatch,
                    replace: soundboardActionSelectionReplacement,
                },
            ],
        },
        {
            // Emoji and reaction pickers share the same native grid. Inject the
            // matching FavoriteRandom section into both the rail and the grid.
            find: emojiPickerModuleFind,
            replacement: [
                {
                    match: emojiCategoryPatch,
                    replace: emojiCategoryReplacement,
                },
                {
                    match: emojiGridCategoriesPatch,
                    replace: emojiGridCategoriesReplacement,
                },
                {
                    match: emojiCategoryItemsPatch,
                    replace: emojiCategoryItemsReplacement,
                },
                {
                    match: emojiActionButtonClassPatch,
                    replace: emojiActionButtonClassReplacement,
                },
                {
                    match: emojiActionButtonContentPatch,
                    replace: emojiActionButtonContentReplacement,
                },
                {
                    match: emojiCategoryIconPatch,
                    replace: emojiCategoryIconReplacement,
                },
                {
                    match: emojiCategoryLabelPatch,
                    replace: emojiCategoryLabelReplacement,
                },
                {
                    match: emojiSelectionPatch,
                    replace: emojiSelectionReplacement,
                },
            ],
        },
        {
            // Sticker categories and their native action tile.
            find: "stickers-you-might-like-header",
            replacement: [
                {
                    match: stickerRailCategoriesPatch,
                    replace: stickerRailCategoriesReplacement,
                },
                {
                    match: stickerGridCategoriesPatch,
                    replace: stickerGridCategoriesReplacement,
                },
                {
                    match: stickerMouseSelectionPatch,
                    replace: stickerMouseSelectionReplacement,
                },
                {
                    match: stickerKeyboardSelectionPatch,
                    replace: stickerKeyboardSelectionReplacement,
                },
                {
                    match: stickerButtonLabelPatch,
                    replace: stickerButtonLabelReplacement,
                },
                {
                    match: stickerCategoryRailPatch,
                    replace: stickerCategoryRailReplacement,
                },
            ],
        },
        {
            // Transform only our marker sticker after Discord builds its grid.
            find: stickerGridModuleFind,
            replacement: {
                match: stickerGridResultPatch,
                replace: stickerGridResultReplacement,
            },
        },
    ],

    chatBarButton: {
        icon: RandomFavoritesIcon,
        render: RandomFavoritesButton,
    },

    addRandomSoundboardCategory,
    addRandomEmojiCategory,
    addRandomEmojiGridCategoryIds,
    addRandomStickerCategory,
    getRandomEmojiCategoryLabel,
    getRandomEmojiCategoryItems,
    getRandomEmojiPickerActionClass,
    getRandomPickerButtonLabel,
    getRandomPickerCategoryLabel,
    handleRandomEmojiSelection,
    handleRandomPickerGridItem,
    handleRandomSoundboardSelection,
    isRandomEmojiCategoryId,
    isRandomStickerCategory,
    renderRandomPickerIcon,
    renderRandomEmojiPickerActionContent,
    transformRandomStickerGrid,

    start() {
        startRandomSoundboardIntegration();
    },

    stop() {
        stopRandomSoundboardIntegration();
        activeChannels.clear();
        resetFavoriteSelection();
        reactionPicker.clear();
        resetExpressionPickerCaches();
    },
});
