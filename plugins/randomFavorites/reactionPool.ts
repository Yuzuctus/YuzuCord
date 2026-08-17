/*
 * Vencord, a Discord client mod
 * Copyright (c) 2026 Vendicated and contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

export interface ReactionEmojiIdentity {
    id?: string;
    surrogates?: string;
    type: number;
}

export function reactionEmojiKey(emoji: ReactionEmojiIdentity) {
    return emoji.type === 0
        ? `unicode:${emoji.surrogates}`
        : `custom:${emoji.id}`;
}

export function buildReactionEmojiPool<T extends ReactionEmojiIdentity>(
    emojis: readonly T[],
    isUsable: (emoji: T) => boolean,
) {
    const unique = new Map<string, T>();

    for (const emoji of emojis) {
        if (!isUsable(emoji)) continue;
        unique.set(reactionEmojiKey(emoji), emoji);
    }

    return Array.from(unique.values());
}
