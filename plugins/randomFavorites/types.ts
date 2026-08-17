/*
 * Vencord, a Discord client mod
 * Copyright (c) 2026 Vendicated and contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import type { Channel, SoundboardSound } from "@vencord/discord-types";

import type { SoundboardSnapshot } from "./_shared/soundboard/src/attachment";
import type { FavoriteGifMedia, PreviewSource } from "./previewMedia";

export type FavoriteKind = "all" | "gif" | "emoji" | "sticker" | "soundboard";
export type ConcreteFavoriteKind = Exclude<FavoriteKind, "all">;
export type MixMode = "balanced" | "uniform";
export type PoolScope = "favorites" | "all";

export interface FavoriteGif extends FavoriteGifMedia {
    width?: number;
    height?: number;
    order?: number;
}

export interface FrecencySettings {
    favoriteGifs?: {
        gifs?: Record<string, FavoriteGif>;
    };
    favoriteStickers?: {
        stickerIds?: Array<string | bigint | number>;
    };
    favoriteEmojis?: {
        emojis?: Array<string | bigint | number>;
    };
}

export interface FrecencySettingsActions {
    getCurrentValue(): FrecencySettings | undefined;
}

export interface FavoriteCandidate {
    kind: ConcreteFavoriteKind;
    key: string;
    label: string;
    content?: string;
    previewType?: "image" | "lottie" | "audio";
    previewUrl?: string;
    previewSources?: PreviewSource[];
    stickerId?: string;
    soundboard?: SoundboardSnapshot;
}

export interface FavoritePools {
    candidates: Record<ConcreteFavoriteKind, FavoriteCandidate[]>;
    rawCounts: Record<ConcreteFavoriteKind, number>;
    collectionErrors: Partial<Record<ConcreteFavoriteKind, string>>;
}

export type SendResult =
    | { ok: true; candidate: FavoriteCandidate; }
    | { ok: false; message: string; };

export interface SelectedSendResult {
    sentCount: number;
    errors: string[];
}

export interface FavoriteDrawResult {
    candidates: FavoriteCandidate[];
    errors: string[];
}

export interface SoundboardDrawResult {
    error?: string;
    sound?: SoundboardSound;
}

export interface SoundboardSendPreparation {
    channel?: Channel;
    error?: string;
    sound?: SoundboardSound;
}

export interface ChatSoundboardCollection {
    candidates: FavoriteCandidate[];
    error?: string;
    rawCount: number;
}
