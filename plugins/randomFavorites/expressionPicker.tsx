/*
 * Vencord, a Discord client mod
 * Copyright (c) 2026 Vendicated and contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import type { Emoji, SoundboardSound } from "@vencord/discord-types";
import { EmojiStore, ExpressionPickerStore } from "@webpack/common";

import { isFrench, localize } from "./localization";
import { insertAfterFavoritesOrFirst } from "./pickerCategoryOrder";

export type RandomSoundboardAction = "direct" | "preview";
export type RandomReactionAction = "direct" | "preview";

export type RandomPickerEmoji = Emoji & {
    randomFavoritesAction?: RandomReactionAction;
    randomFavoritesKind: "emoji" | "reaction";
};

export interface NativeEmojiSelection {
    emoji?: RandomPickerEmoji;
    isBurst?: boolean;
    willClose?: boolean;
}

export type NativeEmojiSelect = (selection: NativeEmojiSelection) => unknown;

interface RandomSoundboardActionSound extends SoundboardSound {
    randomFavoritesAction: RandomSoundboardAction;
}

interface RandomSoundboardGridItem {
    index: number;
    sound: RandomSoundboardActionSound;
    type: number;
}

interface RandomStickerCategory {
    id: string;
    name: string;
    randomFavoritesCategory: true;
    stickers: readonly RandomStickerSource[];
    type: string;
}

interface RandomStickerSource {
    description: string;
    format_type: number;
    id: string;
    name: string;
    pack_id: string;
    randomFavoritesKind: "sticker";
    type: number;
}

export interface RandomStickerGridItem {
    name?: string;
    randomFavoritesKind?: "sticker";
    sticker?: RandomStickerSource;
    type: number;
    [key: string]: unknown;
}

interface RandomStickerGridResult {
    columnCounts: readonly number[];
    gutterWidth: number;
    rowCount: number;
    rowCountBySection: readonly number[];
    stickersGrid: readonly (readonly RandomStickerGridItem[])[];
}

export const REACTION_EMOJI_INTENTION = 0;
const CHAT_EMOJI_INTENTION = 3;
const RANDOM_EMOJI_CATEGORY_ID = "FavoriteRandom";
const RANDOM_REACTION_CATEGORY_ID = "FavoriteRandomReaction";
const RANDOM_STICKER_CATEGORY_ID = "vc-rf-random-sticker";
const RANDOM_STICKER_ITEM_ID = "vc-rf-random-sticker-action";

const randomEmojiCategoryObjects = new Map<string, object>();
const randomEmojiCategoryItems = new Map<string, RandomPickerEmoji[]>();
let randomEmojiGridCategoriesCache = new WeakMap<
    readonly string[],
    Map<number, readonly string[]>
>();
let randomEmojiRailCategoriesCache = new WeakMap<
    readonly object[],
    Map<number, readonly object[]>
>();

export function getActiveExpressionPickerView() {
    const expressionPickerState = (
        ExpressionPickerStore.useExpressionPickerStore as typeof ExpressionPickerStore.useExpressionPickerStore & {
            getState?(): { activeView?: string | null; };
        }
    ).getState?.();

    return expressionPickerState?.activeView;
}

export function isRandomSoundboardActionSound(
    sound: SoundboardSound | null | undefined,
): sound is RandomSoundboardActionSound {
    return sound != null
        && (sound as Partial<RandomSoundboardActionSound>).randomFavoritesAction != null;
}

export function createRandomSoundboardGridItems(
    virtualGuildId: string,
): RandomSoundboardGridItem[] {
    const actions: Array<{
        action: RandomSoundboardAction;
        emojiName: string;
        name: string;
    }> = [
        {
            action: "direct",
            emojiName: "🎲",
            name: localize("Play directly", "Lecture directe"),
        },
        {
            action: "preview",
            emojiName: "🛡️",
            name: localize("Safe preview", "Aperçu sécurisé"),
        },
    ];

    return actions.map(({ action, emojiName, name }, index) => ({
        index,
        type: 0,
        sound: {
            available: true,
            emojiId: null,
            emojiName,
            guildId: virtualGuildId,
            name,
            randomFavoritesAction: action,
            soundId: `vc-rf-${action}`,
            volume: 1,
        },
    }));
}

export function addRandomEmojiCategory<T extends {
    id?: string;
    type?: string;
}>(
    categories: readonly T[],
    pickerIntention: number,
): readonly T[] {
    const categoryId = randomEmojiCategoryIdForIntention(pickerIntention);
    if (
        !categoryId
        || categories.some(category => category.id === categoryId)
    ) {
        return categories;
    }

    const source = categories as readonly object[];
    const cached = randomEmojiRailCategoriesCache
        .get(source)
        ?.get(pickerIntention) as readonly T[] | undefined;
    if (cached) return cached;

    let randomCategory = randomEmojiCategoryObjects.get(categoryId) as T | undefined;
    if (!randomCategory) {
        randomCategory = {
            id: categoryId,
            isNitroLocked: false,
            name: "FavoriteRandom",
            randomFavoritesCategory: true,
            type: "UNICODE",
        } as unknown as T;
        randomEmojiCategoryObjects.set(categoryId, randomCategory);
    }

    const result = insertAfterFavoritesOrFirst(
        categories,
        randomCategory,
        category => category.id,
    );
    const intentionCache = randomEmojiRailCategoriesCache.get(source) ?? new Map();
    intentionCache.set(pickerIntention, result as readonly object[]);
    randomEmojiRailCategoriesCache.set(source, intentionCache);
    return result;
}

export function addRandomEmojiGridCategoryIds(
    categoryIds: readonly string[],
    pickerIntention: number,
): readonly string[] {
    const categoryId = randomEmojiCategoryIdForIntention(pickerIntention);
    if (
        !categoryId
        || categoryIds.includes(categoryId)
    ) {
        return categoryIds;
    }

    const cached = randomEmojiGridCategoriesCache
        .get(categoryIds)
        ?.get(pickerIntention);
    if (cached) return cached;

    const result = insertAfterFavoritesOrFirst(categoryIds, categoryId, id => id);
    const intentionCache = randomEmojiGridCategoriesCache.get(categoryIds) ?? new Map();
    intentionCache.set(pickerIntention, result);
    randomEmojiGridCategoriesCache.set(categoryIds, intentionCache);
    return result;
}

export function getRandomEmojiCategoryItems(
    categoryId: string,
): RandomPickerEmoji[] | undefined {
    if (!isRandomEmojiCategoryId(categoryId)) return;

    const cacheKey = `${categoryId}:${isFrench() ? "fr" : "en"}`;
    const cached = randomEmojiCategoryItems.get(cacheKey);
    if (cached) return cached;

    const emojiContext = EmojiStore.getDisambiguatedEmojiContext(null);
    const directEmoji = emojiContext.getByName("game_die");
    if (!directEmoji) return [];

    if (categoryId === RANDOM_EMOJI_CATEGORY_ID) {
        const items = [createRandomPickerEmoji(
            directEmoji,
            "emoji",
            undefined,
            localize("Random emoji", "Emote aléatoire"),
        )];
        randomEmojiCategoryItems.set(cacheKey, items);
        return items;
    }

    const previewEmoji = emojiContext.getByName("shield")
        ?? emojiContext.getByName("eyes");

    const items = [
        createRandomPickerEmoji(
            directEmoji,
            "reaction",
            "direct",
            localize("Direct reaction", "Réaction directe"),
        ),
        ...(previewEmoji
            ? [createRandomPickerEmoji(
                previewEmoji,
                "reaction",
                "preview",
                localize("Safe preview", "Aperçu sécurisé"),
            )]
            : []),
    ];
    randomEmojiCategoryItems.set(cacheKey, items);
    return items;
}

export function isRandomEmojiCategoryId(categoryId: string) {
    return categoryId === RANDOM_EMOJI_CATEGORY_ID
        || categoryId === RANDOM_REACTION_CATEGORY_ID;
}

export function getRandomEmojiCategoryLabel(categoryId: string) {
    return isRandomEmojiCategoryId(categoryId) ? "FavoriteRandom" : undefined;
}

function randomEmojiCategoryIdForIntention(pickerIntention: number) {
    if (pickerIntention === CHAT_EMOJI_INTENTION)
        return RANDOM_EMOJI_CATEGORY_ID;
    if (pickerIntention === REACTION_EMOJI_INTENTION)
        return RANDOM_REACTION_CATEGORY_ID;
    return undefined;
}

function createRandomPickerEmoji(
    emoji: Emoji,
    kind: RandomPickerEmoji["randomFavoritesKind"],
    action?: RandomReactionAction,
    name?: string,
): RandomPickerEmoji {
    const randomEmoji = Object.create(emoji) as RandomPickerEmoji;
    Object.defineProperties(randomEmoji, {
        ...(name
            ? {
                name: {
                    enumerable: true,
                    value: name,
                },
            }
            : {}),
        randomFavoritesAction: {
            enumerable: true,
            value: action,
        },
        randomFavoritesKind: {
            enumerable: true,
            value: kind,
        },
    });
    return randomEmoji;
}

export function getRandomEmojiPickerActionClass(emoji?: RandomPickerEmoji) {
    return emoji?.randomFavoritesKind
        ? "vc-rf-picker-action"
        : undefined;
}

export function renderRandomEmojiPickerActionContent(emoji?: RandomPickerEmoji) {
    if (!emoji?.randomFavoritesKind) return;

    const icon = emoji.randomFavoritesAction === "preview" ? "🛡️" : "🎲";
    return (
        <span className="vc-rf-picker-action-content">
            <span className="vc-rf-picker-action-icon" aria-hidden="true">
                {icon}
            </span>
            <span className="vc-rf-picker-action-label">{emoji.name}</span>
        </span>
    );
}

export function addRandomStickerCategory<T extends {
    id?: string;
    type?: string;
}>(categories: readonly T[]): readonly T[] {
    if (categories.some(category => category.id === RANDOM_STICKER_CATEGORY_ID))
        return categories;

    const randomCategory: RandomStickerCategory = {
        id: RANDOM_STICKER_CATEGORY_ID,
        name: "FavoriteRandom",
        randomFavoritesCategory: true,
        stickers: [{
            description: localize(
                "Send a random favorite sticker",
                "Envoyer un sticker favori aléatoire",
            ),
            format_type: 1,
            id: RANDOM_STICKER_ITEM_ID,
            name: localize("Random sticker", "Sticker aléatoire"),
            pack_id: RANDOM_STICKER_CATEGORY_ID,
            randomFavoritesKind: "sticker",
            type: 1,
        }],
        type: "FAVORITE",
    };
    const favoritesIndex = categories.findIndex(category => category.type === "FAVORITE");
    const insertionIndex = favoritesIndex >= 0 ? favoritesIndex + 1 : 0;

    return [
        ...categories.slice(0, insertionIndex),
        randomCategory as unknown as T,
        ...categories.slice(insertionIndex),
    ];
}

export function isRandomStickerCategory(category?: { id?: string; }) {
    return category?.id === RANDOM_STICKER_CATEGORY_ID;
}

export function transformRandomStickerGrid<T extends RandomStickerGridResult>(result: T): T {
    let changed = false;
    const stickersGrid = result.stickersGrid.map(row => row.map(item => {
        if (item.sticker?.randomFavoritesKind !== "sticker") return item;

        changed = true;
        return {
            ...item,
            guild_id: RANDOM_STICKER_CATEGORY_ID,
            name: localize("Random sticker", "Sticker aléatoire"),
            randomFavoritesKind: "sticker" as const,
            type: 1,
        };
    }));

    return changed
        ? { ...result, stickersGrid } as T
        : result;
}

export function getRandomPickerCategoryLabel(category?: { id?: string; }) {
    return isRandomStickerCategory(category) ? "FavoriteRandom" : undefined;
}

export function getRandomPickerButtonLabel(item?: RandomStickerGridItem) {
    return item?.randomFavoritesKind === "sticker"
        ? localize("Random sticker", "Sticker aléatoire")
        : undefined;
}

export function resetExpressionPickerCaches() {
    randomEmojiCategoryItems.clear();
    randomEmojiCategoryObjects.clear();
    randomEmojiGridCategoriesCache = new WeakMap();
    randomEmojiRailCategoriesCache = new WeakMap();
}
