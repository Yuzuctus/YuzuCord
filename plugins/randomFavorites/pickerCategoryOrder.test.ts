/*
 * Vencord, a Discord client mod
 * Copyright (c) 2026 Vendicated and contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import assert from "node:assert/strict";
import { test } from "node:test";

import { insertAfterFavoritesOrFirst } from "./pickerCategoryOrder";

const getId = (item: { id: string; }) => item.id;

test("picker category is inserted immediately after favorites", () => {
    const categories = [
        { id: "recent" },
        { id: "favorites" },
        { id: "guild" },
    ];

    assert.deepEqual(
        insertAfterFavoritesOrFirst(categories, { id: "FavoriteRandom" }, getId)
            .map(category => category.id),
        ["recent", "favorites", "FavoriteRandom", "guild"],
    );
});

test("picker category never becomes the initial native category", () => {
    const categories = [
        { id: "frequently-used" },
        { id: "guild" },
    ];

    assert.deepEqual(
        insertAfterFavoritesOrFirst(categories, { id: "FavoriteRandom" }, getId)
            .map(category => category.id),
        ["frequently-used", "FavoriteRandom", "guild"],
    );
});

test("picker category insertion is idempotent", () => {
    const categories = [
        { id: "favorites" },
        { id: "FavoriteRandom" },
    ];

    assert.equal(
        insertAfterFavoritesOrFirst(categories, { id: "FavoriteRandom" }, getId),
        categories,
    );
});
