/*
 * Vencord, a Discord client mod
 * Copyright (c) 2026 Vendicated and contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

const identifier = String.raw`[$A-Z_a-z][$\w]*`;

// These anchors are intentionally module-specific. Generic expression-picker
// markers also exist in the sticker picker and can make Vencord consume a patch
// before reaching the module that owns the matching implementation.
export const emojiPickerModuleFind = "useEmojiGrid";
export const stickerGridModuleFind = "stickerFrecencyWithoutFetchingLatest.frequently";

export const soundboardActionSelectionPatch = new RegExp(
    String.raw`(${identifier})=(${identifier})\.useCallback\(\((${identifier}),(${identifier})\)=>\{switch\(\3\.item\.type\)\{case (${identifier})\.uq\.SOUND:`,
);

export const soundboardActionSelectionReplacement =
    "$1=$2.useCallback(($3,$4)=>{if($self.handleRandomSoundboardSelection($3.item?.sound))return;switch($3.item.type){case $5.uq.SOUND:";

export const emojiCategoryPatch = new RegExp(
    String.raw`(${identifier})=\(0,(${identifier})\.ss\)\((${identifier}),(${identifier}),\4\?\.guild_id\?\?(${identifier}),(${identifier})\)`,
);

export const emojiCategoryReplacement =
    "$1=$self.addRandomEmojiCategory((0,$2.ss)($3,$4,$4?.guild_id??$5,$6),$3)";

// The category rail and the emoji grid use two different category arrays.
// Patching only `ss(...)` adds the shortcut on the left but never creates the
// matching section in the grid. This anchor targets the categories consumed by
// useEmojiGrid and keeps the current picker intention available to our helper.
export const emojiGridCategoriesPatch = new RegExp(
    String.raw`(pickerIntention:(${identifier}),emojiSearchResults:${identifier},gridWidth:${identifier},emojiPaddingHorizontal:${identifier},emojiSpriteSize:${identifier},shouldShowSoundmojiInEmojiPicker:${identifier},showOnlyUnicode:(${identifier})\}=(${identifier}),(${identifier})=.{0,160}?\.categories\),)(${identifier})=(${identifier})\.useMemo\(\(\)=>\3\?(${identifier})\.Ay\.getCategories\(\):\5,\[\5,\3\]\)`,
);

export const emojiGridCategoriesReplacement =
    "$1$6=$7.useMemo(()=>$self.addRandomEmojiGridCategoryIds($3?$8.Ay.getCategories():$5,$2),[$5,$3,$2])";

export const emojiCategoryItemsPatch = new RegExp(
    String.raw`let (${identifier})=(${identifier})\.Ay\.getByCategory\((${identifier})\);null!=\1&&`,
);

export const emojiCategoryItemsReplacement =
    "let $1=$self.getRandomEmojiCategoryItems($3)??$2.Ay.getByCategory($3);null!=$1&&";

export const emojiActionButtonClassPatch = new RegExp(
    String.raw`(let ${identifier}=${identifier}\.forwardRef\(function\(${identifier},${identifier}\)\{let ${identifier},\{emoji:(${identifier}),.{0,900}?className:${identifier}\(\)\()`,
);

export const emojiActionButtonClassReplacement =
    "$1$self.getRandomEmojiPickerActionClass($2),";

export const emojiActionButtonContentPatch = new RegExp(
    String.raw`(let ${identifier}=${identifier}\.forwardRef\(function\(${identifier},${identifier}\)\{let ${identifier},\{emoji:(${identifier}),.{0,1800}?"data-animated":\2\.animated\?"true":null,ref:${identifier},children:)(\(0,${identifier}\.jsx\)\(${identifier},\{)`,
);

export const emojiActionButtonContentReplacement =
    "$1$self.renderRandomEmojiPickerActionContent($2)??$3";

export const emojiCategoryIconPatch = new RegExp(
    String.raw`(let ${identifier}=${identifier}\.memo\(function\(${identifier}\)\{let\{categoryId:(${identifier}),\.\.\.(${identifier})\}=${identifier}),(${identifier})=function\(`,
);

export const emojiCategoryIconReplacement =
    "$1;if($self.isRandomEmojiCategoryId($2))return $self.renderRandomPickerIcon($3);let $4=function(";

export const emojiCategoryLabelPatch = new RegExp(
    String.raw`null!=(${identifier})&&\((${identifier})=\(0,(${identifier})\.Nu\)\(\1,(${identifier})\?\.name\)\)`,
);

export const emojiCategoryLabelReplacement =
    "null!=$1&&($2=$self.getRandomEmojiCategoryLabel($1)??(0,$3.Nu)($1,$4?.name))";

// Intercept at the common EmojiPicker selection boundary. Unlike the outer
// expression picker, this path is also used by the message reaction picker.
export const emojiSelectionPatch = new RegExp(
    String.raw`(${identifier})\(\{emoji:(${identifier}),willClose:(${identifier})\.isFinalSelection,isBurst:\3\.isBurst\}\)`,
);

export const emojiSelectionReplacement =
    "$self.handleRandomEmojiSelection($1,{emoji:$2,willClose:$3.isFinalSelection,isBurst:$3.isBurst})||$1({emoji:$2,willClose:$3.isFinalSelection,isBurst:$3.isBurst})";

export const stickerRailCategoriesPatch = new RegExp(
    String.raw`(${identifier})=\(0,(${identifier})\.pD\)\((${identifier})\),\{firstStandardStickerCategoryIndex:`,
);

export const stickerRailCategoriesReplacement =
    "$1=$self.addRandomStickerCategory((0,$2.pD)($3)),{firstStandardStickerCategoryIndex:";

// The sticker picker also asks for categories independently when it builds the
// central grid. Keep this separate from the rail patch so both surfaces always
// receive the same virtual category.
export const stickerGridCategoriesPatch = new RegExp(
    String.raw`(${identifier})=\(0,(${identifier})\.pD\)\((${identifier})\),(${identifier})=0===\1\.filter\(`,
);

export const stickerGridCategoriesReplacement =
    "$1=$self.addRandomStickerCategory((0,$2.pD)($3)),$4=0===$1.filter(";

export const stickerGridResultPatch = new RegExp(
    String.raw`return\{rowCount:(${identifier}),rowCountBySection:(${identifier}),stickersGrid:(${identifier}),gutterWidth:(${identifier}),columnCounts:(${identifier})\}`,
);

export const stickerGridResultReplacement =
    "return $self.transformRandomStickerGrid({rowCount:$1,rowCountBySection:$2,stickersGrid:$3,gutterWidth:$4,columnCounts:$5})";

export const stickerMouseSelectionPatch = new RegExp(
    String.raw`onClick:function\(\)\{(${identifier})\.type===(${identifier})\.op\.CREATE_STICKER&&`,
);

export const stickerMouseSelectionReplacement =
    "onClick:function(){if($self.handleRandomPickerGridItem($1))return;$1.type===$2.op.CREATE_STICKER&&";

export const stickerKeyboardSelectionPatch = new RegExp(
    String.raw`switch\((${identifier})\.type\)\{case (${identifier})\.op\.CREATE_STICKER:(?=${identifier}\.default\.track)`,
);

export const stickerKeyboardSelectionReplacement =
    "switch($1.type){case $2.op.CREATE_STICKER:if($self.handleRandomPickerGridItem($1))break;";

export const stickerButtonLabelPatch = new RegExp(
    String.raw`(switch\((${identifier})\.type\)\{case ${identifier}\.op\.CREATE_STICKER:return.{0,1400}?children:)(${identifier})\.intl\.string\(\3\.t\["\+nEuqr"\]\)`,
);

export const stickerButtonLabelReplacement =
    "$1$self.getRandomPickerButtonLabel($2)??$3.intl.string($3.t[\"+nEuqr\"])";

export const stickerCategoryRailPatch = new RegExp(
    String.raw`(${identifier})=(${identifier})\.type===(${identifier})\.Z2\.PACK,(${identifier})="",(${identifier})=null;`,
);

export const stickerCategoryRailReplacement =
    "$1=$self.isRandomStickerCategory($2)?false:$2.type===$3.Z2.PACK,$4=$self.getRandomPickerCategoryLabel($2)??\"\",$5=$self.isRandomStickerCategory($2)?$self.renderRandomPickerIcon({height:32,width:32,style:{display:\"block\"}}):null;";
