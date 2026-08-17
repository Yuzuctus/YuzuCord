/*
 * Vencord, a Discord client mod
 * Copyright (c) 2026 Vendicated and contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import { LocaleStore } from "@webpack/common";

export function isFrench() {
    try {
        return LocaleStore.locale?.toLowerCase().startsWith("fr") ?? false;
    } catch {
        return false;
    }
}

export function localize(english: string, french: string) {
    return isFrench() ? french : english;
}
