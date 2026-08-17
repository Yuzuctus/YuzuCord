/*
 * Vencord, a Discord client mod
 * Copyright (c) 2026 Vendicated and contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import { definePluginSettings } from "@api/Settings";
import { OptionType } from "@utils/types";

import { DEFAULT_SOUNDBOARD_FILE_NAME } from "./_shared/soundboard/src/attachment";
import type { RepeatStrength } from "./adaptiveRandom";
import { localize } from "./localization";

export const settings = definePluginSettings({
    showChatBarButton: {
        type: OptionType.BOOLEAN,
        get displayName() {
            return localize("Chat bar button", "Bouton dans la barre de chat");
        },
        get description() {
            return localize(
                "Show the Random Favorites dice button in the chat bar.",
                "Affiche le bouton dé de Random Favorites dans la barre de chat.",
            );
        },
        default: true,
    },
    previewBeforeSend: {
        type: OptionType.BOOLEAN,
        get displayName() {
            return localize("Safe preview before sending", "Aperçu sécurisé avant envoi");
        },
        get description() {
            return localize(
                "Show random GIFs, emojis, stickers, and soundboard sounds privately before sending them.",
                "Affiche les GIFs, emotes, stickers et sons du soundboard aléatoires en privé avant de les envoyer.",
            );
        },
        default: false,
    },
    maskGifs: {
        type: OptionType.BOOLEAN,
        get displayName() {
            return localize("Mask random GIFs", "Masquer les GIFs aléatoires");
        },
        get description() {
            return localize(
                "Hide random GIFs behind Discord's native spoiler mask.",
                "Cache les GIFs aléatoires derrière le spoiler natif de Discord.",
            );
        },
        default: true,
    },
    showGifLabel: {
        type: OptionType.BOOLEAN,
        get displayName() {
            return localize("Show the GIF message", "Afficher le texte des GIFs");
        },
        get description() {
            return localize(
                "Add a short message before every random GIF.",
                "Ajoute un petit texte avant chaque GIF aléatoire.",
            );
        },
        default: true,
    },
    gifLabel: {
        type: OptionType.STRING,
        get displayName() {
            return localize("GIF message", "Texte des GIFs");
        },
        get description() {
            return localize(
                "Text displayed before random GIFs.",
                "Texte affiché avant les GIFs aléatoires.",
            );
        },
        get default() {
            return localize("Random GIF:", "Gif random :");
        },
        get placeholder() {
            return localize("Random GIF:", "Gif random :");
        },
    },
    sendEachSelectedType: {
        type: OptionType.BOOLEAN,
        get displayName() {
            return localize(
                "One item from each selected type",
                "Un élément de chaque type coché",
            );
        },
        get description() {
            return localize(
                "When enabled, a left click sends one item from every selected type. When disabled, it sends only one item chosen from all selected types.",
                "Activé, le clic gauche envoie un élément de chaque type coché. Désactivé, il envoie un seul élément choisi parmi tous les types cochés.",
            );
        },
        default: true,
    },
    sendGifsOnLeftClick: {
        type: OptionType.BOOLEAN,
        get displayName() {
            return localize("GIFs on left click", "GIFs au clic gauche");
        },
        get description() {
            return localize(
                "Send one random favorite GIF when left-clicking the chat bar button.",
                "Envoie un GIF favori aléatoire avec le clic gauche sur le bouton de la barre de chat.",
            );
        },
        default: true,
    },
    sendEmojisOnLeftClick: {
        type: OptionType.BOOLEAN,
        get displayName() {
            return localize("Emojis on left click", "Emotes au clic gauche");
        },
        get description() {
            return localize(
                "Send one random emoji when left-clicking the chat bar button.",
                "Envoie une emote aléatoire avec le clic gauche sur le bouton de la barre de chat.",
            );
        },
        default: true,
    },
    sendStickersOnLeftClick: {
        type: OptionType.BOOLEAN,
        get displayName() {
            return localize("Stickers on left click", "Stickers au clic gauche");
        },
        get description() {
            return localize(
                "Send one random sticker when left-clicking the chat bar button.",
                "Envoie un sticker aléatoire avec le clic gauche sur le bouton de la barre de chat.",
            );
        },
        default: true,
    },
    sendSoundboardsOnLeftClick: {
        type: OptionType.BOOLEAN,
        get displayName() {
            return localize("Soundboards on left click", "Soundboards au clic gauche");
        },
        get description() {
            return localize(
                "Send one random accessible soundboard sound as an audio attachment when left-clicking the chat bar button.",
                "Envoie un son de soundboard aléatoire accessible sous forme de pièce jointe audio avec le clic gauche sur le bouton de la barre de chat.",
            );
        },
        default: false,
    },
    soundboardFileName: {
        type: OptionType.STRING,
        get displayName() {
            return localize("Soundboard attachment name", "Nom du fichier soundboard");
        },
        get description() {
            return localize(
                "Base filename used for random soundboard audio attachments. The correct extension is added automatically.",
                "Nom de base utilisé pour les pièces jointes audio du soundboard aléatoire. L’extension correcte est ajoutée automatiquement.",
            );
        },
        default: DEFAULT_SOUNDBOARD_FILE_NAME,
        placeholder: DEFAULT_SOUNDBOARD_FILE_NAME,
    },
    mixMode: {
        type: OptionType.SELECT,
        get displayName() {
            return localize(
                "Mixed-mode type distribution",
                "Répartition des types en mode mixte",
            );
        },
        get description() {
            return localize(
                "How single-item mode and /random-favorite choose between the allowed types.",
                "Détermine comment le mode unique et /random-favorite choisissent entre les types autorisés.",
            );
        },
        get options() {
            return [
                {
                    label: localize(
                        "Balanced distribution (equal base weight per type)",
                        "Répartition équilibrée (même poids de base par type)",
                    ),
                    value: "balanced",
                    default: true,
                },
                {
                    label: localize(
                        "Fully random (equal chance per item)",
                        "Totalement aléatoire (même chance par élément)",
                    ),
                    value: "uniform",
                },
            ] as const;
        },
    },
    emojiPool: {
        type: OptionType.SELECT,
        get displayName() {
            return localize("Emoji source", "Source des emotes");
        },
        get description() {
            return localize(
                "Choose whether random emojis come from favorites or every usable emoji.",
                "Choisis entre les emotes favorites et toutes les emotes utilisables.",
            );
        },
        get options() {
            return [
                {
                    label: localize("Favorite emojis only", "Emotes favorites uniquement"),
                    value: "favorites",
                },
                {
                    label: localize("All usable emojis", "Toutes les emotes utilisables"),
                    value: "all",
                    default: true,
                },
            ] as const;
        },
    },
    stickerPool: {
        type: OptionType.SELECT,
        get displayName() {
            return localize("Sticker source", "Source des stickers");
        },
        get description() {
            return localize(
                "Choose whether random stickers come from favorites or every usable sticker.",
                "Choisis entre les stickers favoris et tous les stickers utilisables.",
            );
        },
        get options() {
            return [
                {
                    label: localize("Favorite stickers only", "Stickers favoris uniquement"),
                    value: "favorites",
                },
                {
                    label: localize("All usable stickers", "Tous les stickers utilisables"),
                    value: "all",
                    default: true,
                },
            ] as const;
        },
    },
    avoidRepeats: {
        type: OptionType.BOOLEAN,
        get displayName() {
            return localize("Reduce repeats", "Limiter les répétitions");
        },
        get description() {
            return localize(
                "Lower the odds of recent items without ever excluding them completely.",
                "Réduit la probabilité des éléments récents sans jamais les exclure complètement.",
            );
        },
        default: true,
    },
    repeatStrength: {
        type: OptionType.SELECT,
        get displayName() {
            return localize(
                "Repeat reduction strength",
                "Intensité anti-répétition",
            );
        },
        get description() {
            return localize(
                "Controls how quickly recent items recover their normal odds.",
                "Contrôle la vitesse à laquelle les éléments récents retrouvent leur probabilité normale.",
            );
        },
        get options() {
            return [
                {
                    label: localize("Light (more surprises)", "Légère (plus de surprises)"),
                    value: "light",
                },
                {
                    label: localize("Balanced", "Équilibrée"),
                    value: "balanced",
                    default: true,
                },
                {
                    label: localize("Strong (fewer repeats)", "Forte (moins de répétitions)"),
                    value: "strong",
                },
            ] as const;
        },
    },
}, {
    gifLabel: {
        disabled() { return !this.store.showGifLabel; },
    },
    repeatStrength: {
        disabled() { return !this.store.avoidRepeats; },
    },
});

export function getRepeatStrength(): RepeatStrength {
    return settings.store.repeatStrength ?? "balanced";
}
