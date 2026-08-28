/*
 * Vencord, a Discord client mod
 * Copyright (c) 2026 Vendicated and contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

export interface ShallowArrayMemo<TResult> {
    clear(): void;
    get(source: readonly unknown[]): TResult | undefined;
    set(source: readonly unknown[], result: TResult): TResult;
}

interface ShallowArrayMemoEntry<TResult> {
    result: TResult;
    source: readonly unknown[];
}

function shallowArrayEquals(left: readonly unknown[], right: readonly unknown[]) {
    return left.length === right.length
        && left.every((item, index) => item === right[index]);
}

/**
 * Memoizes array transformations by their item references instead of only by the
 * array object. Discord sometimes returns a fresh wrapper array on every render
 * while keeping the same category or grid items inside it.
 */
export function createShallowArrayMemo<TResult>(maxEntries = 8): ShallowArrayMemo<TResult> {
    const capacity = Math.max(1, Math.floor(maxEntries));
    let entries: Array<ShallowArrayMemoEntry<TResult>> = [];

    return {
        clear() {
            entries = [];
        },
        get(source) {
            return entries.find(entry => shallowArrayEquals(entry.source, source))?.result;
        },
        set(source, result) {
            const existingIndex = entries.findIndex(entry => shallowArrayEquals(entry.source, source));
            if (existingIndex !== -1) entries.splice(existingIndex, 1);

            entries.unshift({
                result,
                source: source.slice(),
            });
            if (entries.length > capacity) entries.length = capacity;
            return result;
        },
    };
}
