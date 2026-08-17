/*
 * Vencord, a Discord client mod
 * Copyright (c) 2026 Vendicated and contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import type { ComponentProps } from "react";

export function RandomFavoritesIcon({
    height = 24,
    width = 24,
    ...props
}: ComponentProps<"svg">) {
    return (
        <svg
            {...props}
            aria-hidden="true"
            role="img"
            viewBox="0 0 24 24"
            height={height}
            width={width}
            fill="none"
        >
            <rect
                x="3.25"
                y="3.25"
                width="17.5"
                height="17.5"
                rx="4"
                stroke="currentColor"
                strokeWidth="2"
            />
            <circle cx="8" cy="8" r="1.35" fill="currentColor" />
            <circle cx="16" cy="8" r="1.35" fill="currentColor" />
            <circle cx="12" cy="12" r="1.35" fill="currentColor" />
            <circle cx="8" cy="16" r="1.35" fill="currentColor" />
            <circle cx="16" cy="16" r="1.35" fill="currentColor" />
        </svg>
    );
}

export function renderRandomPickerIcon(props: ComponentProps<"svg"> = {}) {
    return <RandomFavoritesIcon height={16} width={16} {...props} />;
}
