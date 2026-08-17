/*
 * Vencord, a Discord client mod
 * Copyright (c) 2026 Vendicated and contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import { strict as assert } from "node:assert";
import { test } from "node:test";
import { Script } from "node:vm";

import {
    emojiActionButtonClassPatch,
    emojiActionButtonClassReplacement,
    emojiActionButtonContentPatch,
    emojiActionButtonContentReplacement,
    emojiCategoryIconPatch,
    emojiCategoryIconReplacement,
    emojiCategoryItemsPatch,
    emojiCategoryItemsReplacement,
    emojiCategoryLabelPatch,
    emojiCategoryLabelReplacement,
    emojiCategoryPatch,
    emojiCategoryReplacement,
    emojiGridCategoriesPatch,
    emojiGridCategoriesReplacement,
    emojiPickerModuleFind,
    emojiSelectionPatch,
    emojiSelectionReplacement,
    soundboardActionSelectionPatch,
    soundboardActionSelectionReplacement,
    stickerButtonLabelPatch,
    stickerButtonLabelReplacement,
    stickerCategoryRailPatch,
    stickerCategoryRailReplacement,
    stickerGridCategoriesPatch,
    stickerGridCategoriesReplacement,
    stickerGridModuleFind,
    stickerGridResultPatch,
    stickerGridResultReplacement,
    stickerKeyboardSelectionPatch,
    stickerKeyboardSelectionReplacement,
    stickerMouseSelectionPatch,
    stickerMouseSelectionReplacement,
    stickerRailCategoriesPatch,
    stickerRailCategoriesReplacement,
} from "./pickerPatches";

test("uses unambiguous Discord module anchors for picker patches", () => {
    const emojiPickerModule = "function useEmojiGrid(){return onSelectSoundmoji}";
    const expressionPickerDecoy = "function StickerPicker(){return onSelectSoundmoji}";
    const stickerGridModule = "stickerFrecencyWithoutFetchingLatest.frequently";
    const stickerFavoritesDecoy = "favoriteStickers?.stickerIds";

    assert.equal(emojiPickerModule.includes(emojiPickerModuleFind), true);
    assert.equal(expressionPickerDecoy.includes(emojiPickerModuleFind), false);
    assert.equal(stickerGridModule.includes(stickerGridModuleFind), true);
    assert.equal(stickerFavoritesDecoy.includes(stickerGridModuleFind), false);
});

test("routes synthetic Soundboard actions before Discord handles native sounds", () => {
    const source = "eK=r.useCallback((e,t)=>{switch(e.item.type){case eu.uq.SOUND:let n=ta[e.category]";
    const patched = source.replace(soundboardActionSelectionPatch, soundboardActionSelectionReplacement);

    assert.match(patched, /handleRandomSoundboardSelection\(e\.item\?\.sound\)/);
    assert.match(patched, /switch\(e\.item\.type\)\{case eu\.uq\.SOUND:/);
});

test("adds the random emoji category and supplies its native emoji item", () => {
    const source = "I=(0,eu.ss)(r,l,l?.guild_id??d,c),f=s.useMemo(()=>u?x:I,[I,u]);function q(e){let{channel:t,fallbackGuildId:n,collapsedSections:i,pickerIntention:r,emojiSearchResults:a,gridWidth:l,emojiPaddingHorizontal:o,emojiSpriteSize:d,shouldShowSoundmojiInEmojiPicker:c,showOnlyUnicode:u}=e,E=(0,_.bG)([C.Ay],()=>C.Ay.categories),A=s.useMemo(()=>u?eJ.Ay.getCategories():E,[E,u]);let t=eJ.Ay.getByCategory(e);null!=t&&I(t,{categoryId:e";
    const patched = source
        .replace(emojiCategoryPatch, emojiCategoryReplacement)
        .replace(emojiGridCategoriesPatch, emojiGridCategoriesReplacement)
        .replace(emojiCategoryItemsPatch, emojiCategoryItemsReplacement);

    assert.match(patched, /addRandomEmojiCategory\(\(0,eu\.ss\)\(r,l,l\?\.guild_id\?\?d,c\),r\)/);
    assert.match(patched, /addRandomEmojiGridCategoryIds\(u\?eJ\.Ay\.getCategories\(\):E,r\)/);
    assert.match(patched, /getRandomEmojiCategoryItems\(e\)\?\?eJ\.Ay\.getByCategory\(e\)/);
});

test("renders the FavoriteRandom emoji category icon and intercepts only its selection", () => {
    const iconSource = "let eq=s.memo(function(e){let{categoryId:t,...n}=e,i=function(e){return e};return i(t)});";
    const labelSource = "null!=r&&(c=(0,eu.Nu)(r,i?.name));";
    const selectionSource = "r({emoji:s,willClose:i.isFinalSelection,isBurst:i.isBurst})";
    const patchedIcon = iconSource.replace(emojiCategoryIconPatch, emojiCategoryIconReplacement);

    assert.match(
        patchedIcon,
        /isRandomEmojiCategoryId\(t\).*renderRandomPickerIcon\(n\)/,
    );
    assert.doesNotThrow(() => new Script(patchedIcon));
    assert.match(
        labelSource.replace(emojiCategoryLabelPatch, emojiCategoryLabelReplacement),
        /getRandomEmojiCategoryLabel\(r\)\?\?\(0,eu\.Nu\)\(r,i\?\.name\)/,
    );
    assert.match(
        selectionSource.replace(emojiSelectionPatch, emojiSelectionReplacement),
        /handleRandomEmojiSelection\(r,\{emoji:s,willClose:i\.isFinalSelection,isBurst:i\.isBurst\}\)\|\|r\(/,
    );
});

test("renders synthetic emoji actions as labelled Discord-style buttons", () => {
    const source = "let nD=s.forwardRef(function(e,t){let n,{emoji:i,isInspected:r,...m}=e,g=(0,_.bG)([q.A],()=>null,[i]);return(0,a.jsx)(ni.vN,{children:(0,a.jsx)(\"button\",{...m,className:o()(nL._X,{[nL.Bx]:r}),\"data-type\":k.g.EMOJI,\"data-id\":i.id,\"data-animated\":i.animated?\"true\":null,ref:t,children:(0,a.jsx)(nO,{\"aria-label\":i.name,emoji:i})})})});";
    const patched = source
        .replace(emojiActionButtonClassPatch, emojiActionButtonClassReplacement)
        .replace(emojiActionButtonContentPatch, emojiActionButtonContentReplacement);

    assert.match(
        patched,
        /className:o\(\)\(\$self\.getRandomEmojiPickerActionClass\(i\),nL\._X/,
    );
    assert.match(
        patched,
        /children:\$self\.renderRandomEmojiPickerActionContent\(i\)\?\?\(0,a\.jsx\)\(nO/,
    );
});

test("materializes a native FavoriteRandom sticker section", () => {
    const source = "c=(0,D.pD)(n),{firstStandardStickerCategoryIndex:u}=r.useMemo(()=>({}));S=(0,D.pD)(s),N=0===S.filter(e=>e.type!==ee.Z2.EMPTY_GUILD_UPSELL).length;return{rowCount:I,rowCountBySection:A,stickersGrid:h,gutterWidth:i,columnCounts:E}";
    const patched = source
        .replace(stickerRailCategoriesPatch, stickerRailCategoriesReplacement)
        .replace(stickerGridCategoriesPatch, stickerGridCategoriesReplacement)
        .replace(stickerGridResultPatch, stickerGridResultReplacement);

    assert.match(patched, /c=\$self\.addRandomStickerCategory\(\(0,D\.pD\)\(n\)\),\{firstStandardStickerCategoryIndex:/);
    assert.match(patched, /S=\$self\.addRandomStickerCategory\(\(0,D\.pD\)\(s\)\),N=0===S\.filter\(/);
    assert.match(patched, /transformRandomStickerGrid\(\{rowCount:I,rowCountBySection:A/);
});

test("routes mouse and keyboard activation of the synthetic sticker tile", () => {
    const mouse = "onClick:function(){e.type===ee.op.CREATE_STICKER&&(Y.default.track";
    const keyboard = "switch(e.type){case ee.op.CREATE_STICKER:Y.default.track";

    assert.match(
        mouse.replace(stickerMouseSelectionPatch, stickerMouseSelectionReplacement),
        /handleRandomPickerGridItem\(e\)/,
    );
    assert.match(
        keyboard.replace(stickerKeyboardSelectionPatch, stickerKeyboardSelectionReplacement),
        /handleRandomPickerGridItem\(e\).*break/,
    );
});

test("keeps Discord's sticker tile and rail while replacing only FavoriteRandom content", () => {
    const label = "switch(e.type){case ee.op.CREATE_STICKER:return(0,i.jsx)(\"div\",{children:(0,i.jsx)(eL.E,{color:\"interactive-text-active\",variant:\"text-xs/normal\",children:eA.intl.string(eA.t[\"+nEuqr\"])})})}";
    const rail = "m=f.type===ee.Z2.PACK,g=\"\",S=null;";

    assert.match(
        label.replace(stickerButtonLabelPatch, stickerButtonLabelReplacement),
        /getRandomPickerButtonLabel\(e\)/,
    );
    assert.match(
        rail.replace(stickerCategoryRailPatch, stickerCategoryRailReplacement),
        /isRandomStickerCategory\(f\)\?false.*renderRandomPickerIcon\(\{height:32,width:32/,
    );
});
