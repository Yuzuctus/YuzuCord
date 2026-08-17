/*
 * Vencord, a Discord client mod
 * Copyright (c) 2026 Vendicated and contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import assert from "node:assert/strict";
import { test } from "node:test";

import { buildReactionEmojiPool, reactionEmojiKey } from "./reactionPool";

interface TestEmoji {
    id?: string;
    name: string;
    surrogates?: string;
    type: number;
    usable: boolean;
}

test("reaction pool keeps every distinct usable Unicode and custom emoji", () => {
    const emojis: TestEmoji[] = [
        { name: "sparkles", surrogates: "✨", type: 0, usable: true },
        { name: "sparkles duplicate", surrogates: "✨", type: 0, usable: true },
        { id: "123", name: "yuzu", type: 1, usable: true },
        { id: "456", name: "filtered", type: 1, usable: false },
    ];

    assert.deepEqual(
        buildReactionEmojiPool(emojis, emoji => emoji.usable).map(emoji => emoji.name),
        ["sparkles duplicate", "yuzu"],
    );
});

test("reaction keys keep Unicode and custom emoji namespaces separate", () => {
    assert.equal(
        reactionEmojiKey({ surrogates: "123", type: 0 }),
        "unicode:123",
    );
    assert.equal(
        reactionEmojiKey({ id: "123", type: 1 }),
        "custom:123",
    );
});
