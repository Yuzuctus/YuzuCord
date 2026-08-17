/*
 * Vencord, a Discord client mod
 * Copyright (c) 2026 Vendicated and contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import { definePluginSettings } from "@api/Settings";
import { Logger } from "@utils/Logger";
import definePlugin, { OptionType } from "@utils/types";
import type { SoundboardSound } from "@vencord/discord-types";
import {
    ChannelStore,
    ExpressionPickerStore,
    LocaleStore,
    SelectedChannelStore,
    showToast,
    Toasts,
} from "@webpack/common";

import { createSoundboardSnapshot } from "./_shared/soundboard/src/attachment";
import {
    canSendSoundboardAttachment,
    ensureSoundboardData,
    sendSoundboardAttachment,
    SoundboardAttachmentError,
} from "./_shared/soundboard/src/runtime";
import {
    soundboardSelectionPatch,
    soundboardSelectionReplacement,
    soundboardTabGatePatch,
    soundboardTabGateReplacement,
} from "./expressionPickerPatch";

type NativeSoundboardSelection = (
    sound: SoundboardSound,
    source: "soundboard_picker",
    metadata: unknown,
) => void;

const logger = new Logger("SoundboardChat");
const pendingSelections = new Set<string>();

function localize(english: string, french: string) {
    return LocaleStore.locale?.toLowerCase().startsWith("fr") ? french : english;
}

const settings = definePluginSettings({
    showSoundboardTab: {
        type: OptionType.BOOLEAN,
        get displayName() {
            return localize("Soundboard tab", "Onglet Soundboard");
        },
        get description() {
            return localize(
                "Add Discord's native Soundboard as the fourth expression picker tab.",
                "Ajoute le Soundboard natif de Discord comme quatrième onglet du sélecteur d'expressions.",
            );
        },
        default: true,
    },
    closePickerAfterSend: {
        type: OptionType.BOOLEAN,
        get displayName() {
            return localize("Close after sending", "Fermer après l'envoi");
        },
        get description() {
            return localize(
                "Close the expression picker after the audio file has been sent.",
                "Ferme le sélecteur d'expressions après l'envoi du fichier audio.",
            );
        },
        default: true,
    },
    fileNameMode: {
        type: OptionType.SELECT,
        get displayName() {
            return localize("Audio file name", "Nom du fichier audio");
        },
        get description() {
            return localize(
                "Use the Soundboard sound name or a fixed custom name.",
                "Utilise le nom du son Soundboard ou un nom personnalisé fixe.",
            );
        },
        options: [
            {
                get label() {
                    return localize("Soundboard sound name", "Nom du son Soundboard");
                },
                value: "sound",
                default: true,
            },
            {
                get label() {
                    return localize("Custom name", "Nom personnalisé");
                },
                value: "custom",
            },
        ],
    },
    customFileName: {
        type: OptionType.STRING,
        get displayName() {
            return localize("Custom file name", "Nom de fichier personnalisé");
        },
        get description() {
            return localize(
                "Used only when the custom name mode is selected. The audio extension is added automatically.",
                "Utilisé uniquement avec le nom personnalisé. L'extension audio est ajoutée automatiquement.",
            );
        },
        default: "Soundboard",
        disabled() {
            return this.store.fileNameMode !== "custom";
        },
    },
    showSuccessToast: {
        type: OptionType.BOOLEAN,
        get displayName() {
            return localize("Sending confirmation", "Confirmation d'envoi");
        },
        get description() {
            return localize(
                "Show a small confirmation after the audio file has been sent.",
                "Affiche une petite confirmation après l'envoi du fichier audio.",
            );
        },
        default: false,
    },
});

async function sendSelectedSound(sound: SoundboardSound) {
    const channelId = SelectedChannelStore.getChannelId();
    const channel = channelId ? ChannelStore.getChannel(channelId) : undefined;
    if (!channel) {
        showToast(
            localize(
                "Open a text channel before selecting a Soundboard sound.",
                "Ouvre un salon textuel avant de sélectionner un son du Soundboard.",
            ),
            Toasts.Type.FAILURE,
        );
        return;
    }

    if (!canSendSoundboardAttachment(channel)) {
        showToast(
            localize(
                "You need permission to send messages and attach files in this channel.",
                "Tu dois pouvoir envoyer des messages et joindre des fichiers dans ce salon.",
            ),
            Toasts.Type.FAILURE,
        );
        return;
    }

    if (pendingSelections.has(channel.id)) {
        showToast(
            localize(
                "A Soundboard sound is already being sent in this channel.",
                "Un son du Soundboard est déjà en cours d'envoi dans ce salon.",
            ),
            Toasts.Type.MESSAGE,
        );
        return;
    }

    pendingSelections.add(channel.id);
    try {
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

        const snapshot = createSoundboardSnapshot(sound);
        await sendSoundboardAttachment(snapshot, channel, {
            fileName: settings.store.fileNameMode === "custom"
                ? settings.store.customFileName
                : snapshot.name,
            localize,
            logger,
        });

        if (settings.store.closePickerAfterSend)
            ExpressionPickerStore.closeExpressionPicker();
        if (settings.store.showSuccessToast) {
            showToast(
                localize("Soundboard audio sent.", "Audio du Soundboard envoyé."),
                Toasts.Type.SUCCESS,
            );
        }
    } catch (error) {
        logger.error("Failed to send the selected Soundboard sound", error);
        showToast(
            error instanceof SoundboardAttachmentError
                ? error.message
                : localize(
                    "The Soundboard audio could not be sent.",
                    "L'audio du Soundboard n'a pas pu être envoyé.",
                ),
            Toasts.Type.FAILURE,
        );
    } finally {
        pendingSelections.delete(channel.id);
    }
}

export default definePlugin({
    name: "SoundboardChat",
    description: "Adds Discord's native Soundboard to the expression picker and sends sounds as audio attachments.",
    authors: [{ name: "Yuzuctus", id: 0n }],
    tags: ["Chat", "Media"],
    settings,

    patches: [{
        find: '"soundboard_picker"',
        replacement: [
            {
                match: soundboardSelectionPatch,
                replace: soundboardSelectionReplacement,
            },
            {
                match: soundboardTabGatePatch,
                replace: soundboardTabGateReplacement,
            },
        ],
    }],

    shouldShowSoundboardTab() {
        return settings.store.showSoundboardTab;
    },

    onSelectSoundboard(
        sound: SoundboardSound,
        nativeSelection: NativeSoundboardSelection | undefined,
        metadata: unknown,
    ) {
        if (!settings.store.showSoundboardTab) {
            nativeSelection?.(sound, "soundboard_picker", metadata);
            return;
        }

        void sendSelectedSound(sound);
    },

    stop() {
        pendingSelections.clear();
    },
});
