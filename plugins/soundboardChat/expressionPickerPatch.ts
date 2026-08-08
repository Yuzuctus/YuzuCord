/*
 * Vencord, a Discord client mod
 * Copyright (c) 2026 Vendicated and contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

const identifier = String.raw`[$A-Z_a-z][$\w]*`;

export const soundboardSelectionPatch = new RegExp(
    String.raw`(${identifier})=(${identifier})\.useCallback\(\((${identifier}),(${identifier})\)=>(${identifier})\?\.\(\3,"soundboard_picker",\4\),\[\5\]\)`,
);

export const soundboardSelectionReplacement =
    "$1=$2.useCallback(($3,$4)=>$self.onSelectSoundboard($3,$5,$4),[$5])";

export const soundboardTabGatePatch = new RegExp(
    String.raw`(${identifier})&&(${identifier})&&((?:\(0,${identifier}\.jsx\))\(${identifier},\{id:${identifier}\.${identifier},"aria-controls":${identifier}\.${identifier},"aria-selected":${identifier}===${identifier}\.${identifier}\.SOUNDBOARD,isActive:${identifier}===${identifier}\.${identifier}\.SOUNDBOARD,viewType:${identifier}\.${identifier}\.SOUNDBOARD,)`,
);

export const soundboardTabGateReplacement =
    "($self.shouldShowSoundboardTab()||$1&&$2)&&$3";
