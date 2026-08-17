/*
 * Vencord, a Discord client mod
 * Copyright (c) 2026 Vendicated and contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import { strict as assert } from "node:assert";
import { test } from "node:test";

import {
    soundboardSelectionPatch,
    soundboardSelectionReplacement,
    soundboardTabGatePatch,
    soundboardTabGateReplacement,
} from "./expressionPickerPatch";

const currentDiscordFixture = [
    "ec=r.useCallback((e,t)=>v?.(e,\"soundboard_picker\",t),[v])",
    "Z&&eu&&(0,i.jsx)(t0,{id:tZ.N6,\"aria-controls\":tZ.AA,\"aria-selected\":Y===eE.kx.SOUNDBOARD,isActive:Y===eE.kx.SOUNDBOARD,viewType:eE.kx.SOUNDBOARD,",
].join(",");

test("redirects only the native Soundboard selection callback", () => {
    const patched = currentDiscordFixture.replace(
        soundboardSelectionPatch,
        soundboardSelectionReplacement,
    );

    assert.match(
        patched,
        /ec=r\.useCallback\(\(e,t\)=>\$self\.onSelectSoundboard\(e,v,t\),\[v\]\)/,
    );
    assert.doesNotMatch(patched, /v\?\.\(e,"soundboard_picker",t\)/);
});

test("keeps Discord's native gate as a fallback while exposing the plugin tab", () => {
    const patched = currentDiscordFixture.replace(
        soundboardTabGatePatch,
        soundboardTabGateReplacement,
    );

    assert.match(patched, /\(\$self\.shouldShowSoundboardTab\(\)\|\|Z&&eu\)&&/);
    assert.match(patched, /viewType:eE\.kx\.SOUNDBOARD/);
});

test("does not touch unrelated expression picker callbacks", () => {
    const emojiCallback = "ed=r.useCallback((e,t)=>v?.(e,\"emoji_picker\",t),[v])";
    assert.equal(
        emojiCallback.replace(soundboardSelectionPatch, soundboardSelectionReplacement),
        emojiCallback,
    );
});
