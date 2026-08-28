/*
 * Vencord, a Discord client mod
 * Copyright (c) 2026 Vendicated and contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import assert from "node:assert/strict";
import { test } from "node:test";

import { createShallowArrayMemo } from "./shallowArrayMemo";

test("returns the same transformation for an equivalent wrapper array", () => {
    const first = { id: "favorites" };
    const second = { id: "guild" };
    const transformed = [first, { id: "FavoriteRandom" }, second];
    const memo = createShallowArrayMemo<readonly object[]>();

    memo.set([first, second], transformed);

    assert.equal(memo.get([first, second]), transformed);
});

test("does not reuse a transformation when an item reference changes", () => {
    const first = { id: "favorites" };
    const memo = createShallowArrayMemo<readonly object[]>();

    memo.set([first], [first]);

    assert.equal(memo.get([{ id: "favorites" }]), undefined);
});

test("clear removes memoized transformations", () => {
    const source = [{ id: "favorites" }];
    const memo = createShallowArrayMemo<readonly object[]>();

    memo.set(source, source);
    memo.clear();

    assert.equal(memo.get(source), undefined);
});
