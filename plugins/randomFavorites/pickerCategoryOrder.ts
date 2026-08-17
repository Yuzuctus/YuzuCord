/*
 * Vencord, a Discord client mod
 * Copyright (c) 2026 Vendicated and contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

export function insertAfterFavoritesOrFirst<T>(
    items: readonly T[],
    insertedItem: T,
    getId: (item: T) => string | undefined,
): readonly T[] {
    const insertedId = getId(insertedItem);
    if (items.some(item => getId(item) === insertedId)) return items;

    const favoritesIndex = items.findIndex(item => getId(item) === "favorites");
    const insertionIndex = favoritesIndex >= 0
        ? favoritesIndex + 1
        : Math.min(1, items.length);

    return [
        ...items.slice(0, insertionIndex),
        insertedItem,
        ...items.slice(insertionIndex),
    ];
}
