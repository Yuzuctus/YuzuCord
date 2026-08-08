/*
 * Vencord, a Discord client mod
 * Copyright (c) 2026 Vendicated and contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import { sendMessage } from "@utils/discord";
import type { Logger } from "@utils/Logger";
import type { Channel, CloudUpload as TCloudUpload } from "@vencord/discord-types";
import { CloudUploadPlatform } from "@vencord/discord-types/enums";
import { findByCodeLazy, findLazy } from "@webpack";
import {
    FluxDispatcher,
    MessageActions,
    PendingReplyStore,
    PermissionsBits,
    PermissionStore,
    SoundboardStore,
} from "@webpack/common";

import {
    buildSoundboardFileName,
    detectSoundboardAudioFormat,
    getSoundboardAudioMimeType,
    isReasonableSoundboardBlob,
    MAX_SOUNDBOARD_AUDIO_BYTES,
    type SoundboardSnapshot,
} from "./attachment";
import { createSharedSoundboardLoader } from "./loader";

type FetchSoundboardSounds = (options?: {
    disableAnalytics?: boolean;
}) => Promise<void>;

type GetSoundboardSoundUrl = (soundId: string) => string;

export type SoundboardAttachmentErrorCode =
    | "busy"
    | "download"
    | "format"
    | "load"
    | "permission"
    | "size"
    | "stale"
    | "timeout"
    | "url";

export class SoundboardAttachmentError extends Error {
    constructor(
        public readonly code: SoundboardAttachmentErrorCode,
        message: string,
    ) {
        super(message);
        this.name = "SoundboardAttachmentError";
    }
}

export interface SoundboardRuntimeContext {
    localize(english: string, french: string): string;
    logger: Pick<Logger, "error">;
}

export interface EnsureSoundboardDataOptions extends SoundboardRuntimeContext {
    onStarted?(): void;
}

export interface SendSoundboardAttachmentOptions extends SoundboardRuntimeContext {
    fileName?: string;
    timeoutMs?: number;
}

const fetchSoundboardSounds = findByCodeLazy(
    "REQUEST_SOUNDBOARD_SOUNDS",
    "SOUNDBOARD_FETCH_DEFAULT_SOUNDS",
) as FetchSoundboardSounds;
const getSoundboardSoundUrl = findByCodeLazy(
    "CDN_HOST",
    ".SOUNDBOARD_SOUND(",
) as GetSoundboardSoundUrl;
const CloudUpload: typeof TCloudUpload = findLazy(
    module => module.prototype?.trackUploadFinished,
);
const loader = createSharedSoundboardLoader();
const activeChannelUploads = new Set<string>();

function createError(
    context: SoundboardRuntimeContext,
    code: SoundboardAttachmentErrorCode,
    english: string,
    french: string,
) {
    return new SoundboardAttachmentError(code, context.localize(english, french));
}

function canSendMessages(channel: Channel) {
    if (channel.isPrivate()) return true;

    const permission = channel.isThread()
        ? PermissionsBits.SEND_MESSAGES_IN_THREADS
        : PermissionsBits.SEND_MESSAGES;
    return PermissionStore.can(permission, channel);
}

export function canSendSoundboardAttachment(channel: Channel) {
    return channel.isPrivate()
        || canSendMessages(channel) && PermissionStore.can(PermissionsBits.ATTACH_FILES, channel);
}

export function resolveSoundboardAudioUrl(soundId: string) {
    try {
        const value = getSoundboardSoundUrl(soundId);
        if (typeof value !== "string" || value.length === 0) return undefined;

        const url = new URL(value);
        if (url.protocol !== "https:") return undefined;
        if (url.hostname !== "cdn.discordapp.com"
            && url.hostname !== "cdn.discordapp.net"
            && url.hostname !== "cdn.discord.com") {
            return undefined;
        }

        return url.toString();
    } catch {
        return undefined;
    }
}

export async function ensureSoundboardData(options: EnsureSoundboardDataOptions) {
    if (SoundboardStore.hasFetchedAllSounds()) return false;

    const { promise, started } = loader.getOrStart(
        () => fetchSoundboardSounds({ disableAnalytics: true }),
    );
    if (started) options.onStarted?.();

    try {
        await promise;
        return started;
    } catch (error) {
        options.logger.error("Failed to load Discord soundboard sounds", error);
        throw createError(
            options,
            "load",
            "Discord could not load the accessible soundboard sounds. Check your connection, then try again.",
            "Discord n'a pas pu charger les sons Soundboard accessibles. Vérifie ta connexion, puis réessaie.",
        );
    }
}

function revalidateSound(
    snapshot: SoundboardSnapshot,
    channel: Channel,
    context: SoundboardRuntimeContext,
) {
    if (!canSendSoundboardAttachment(channel)) {
        throw createError(
            context,
            "permission",
            "Soundboard audio cannot be sent in this channel because you need permission to send messages and attach files.",
            "L'audio du Soundboard ne peut pas être envoyé dans ce salon : il faut pouvoir envoyer des messages et joindre des fichiers.",
        );
    }

    try {
        const currentSound = SoundboardStore.getSound(snapshot.guildId, snapshot.soundId);
        if (!currentSound || currentSound.available === false) {
            throw createError(
                context,
                "stale",
                "This Soundboard sound is no longer available in Discord. Select another sound before sending.",
                "Ce son du Soundboard n'est plus disponible dans Discord. Sélectionne un autre son avant l'envoi.",
            );
        }
    } catch (error) {
        if (error instanceof SoundboardAttachmentError) throw error;

        context.logger.error("Failed to revalidate a Soundboard attachment", error);
        throw createError(
            context,
            "stale",
            "Discord could not validate this Soundboard sound. Select another sound, then try again.",
            "Discord n'a pas pu valider ce son du Soundboard. Sélectionne un autre son, puis réessaie.",
        );
    }
}

async function downloadSoundboardFile(
    snapshot: SoundboardSnapshot,
    options: SendSoundboardAttachmentOptions,
) {
    const url = resolveSoundboardAudioUrl(snapshot.soundId);
    if (!url) {
        throw createError(
            options,
            "url",
            "Discord did not provide a valid Soundboard CDN URL. Select another sound before sending.",
            "Discord n'a pas fourni d'URL CDN valide pour ce son. Sélectionne un autre son avant l'envoi.",
        );
    }

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), options.timeoutMs ?? 15_000);

    try {
        const response = await fetch(url, { signal: controller.signal });
        if (!response.ok) {
            options.logger.error("Soundboard CDN download returned an HTTP error", {
                status: response.status,
            });
            throw createError(
                options,
                "download",
                "Discord could not download this Soundboard sound. Select another one and try again.",
                "Discord n'a pas pu télécharger ce son du Soundboard. Sélectionne-en un autre et réessaie.",
            );
        }

        const contentLength = Number(response.headers.get("content-length"));
        if (Number.isFinite(contentLength) && contentLength > MAX_SOUNDBOARD_AUDIO_BYTES) {
            throw createError(
                options,
                "size",
                "This Soundboard file is too large to send safely.",
                "Ce fichier Soundboard est trop volumineux pour être envoyé en toute sécurité.",
            );
        }

        const blob = await response.blob();
        if (!isReasonableSoundboardBlob(blob)) {
            throw createError(
                options,
                "size",
                "This Soundboard file has an invalid size and was not sent.",
                "La taille de ce fichier Soundboard est invalide : il n'a pas été envoyé.",
            );
        }

        const bytes = new Uint8Array(await blob.arrayBuffer());
        const format = detectSoundboardAudioFormat(
            response.headers.get("content-type") || blob.type,
            bytes,
        );
        if (!format) {
            throw createError(
                options,
                "format",
                "Discord returned an unknown audio format. The sound was not sent.",
                "Discord a retourné un format audio inconnu. Le son n'a pas été envoyé.",
            );
        }

        return new File(
            [bytes],
            buildSoundboardFileName(options.fileName ?? snapshot.name, format),
            { type: getSoundboardAudioMimeType(format) },
        );
    } catch (error) {
        if (error instanceof SoundboardAttachmentError) throw error;

        options.logger.error("Failed to download a Soundboard audio attachment", {
            aborted: controller.signal.aborted,
            error: error instanceof Error ? error.name : "unknown",
        });
        throw createError(
            options,
            controller.signal.aborted ? "timeout" : "download",
            controller.signal.aborted
                ? "The Soundboard download timed out. Try again."
                : "The Soundboard sound could not be downloaded. Try again.",
            controller.signal.aborted
                ? "Le téléchargement du Soundboard a expiré. Réessaie."
                : "Le son du Soundboard n'a pas pu être téléchargé. Réessaie.",
        );
    } finally {
        clearTimeout(timeout);
    }
}

export async function sendSoundboardAttachment(
    snapshot: SoundboardSnapshot,
    channel: Channel,
    options: SendSoundboardAttachmentOptions,
) {
    if (activeChannelUploads.has(channel.id)) {
        throw createError(
            options,
            "busy",
            "A Soundboard sound is already being sent in this channel.",
            "Un son du Soundboard est déjà en cours d'envoi dans ce salon.",
        );
    }

    activeChannelUploads.add(channel.id);
    try {
        revalidateSound(snapshot, channel, options);
        const file = await downloadSoundboardFile(snapshot, options);
        const upload = new CloudUpload({
            file,
            isThumbnail: false,
            platform: CloudUploadPlatform.WEB,
        }, channel.id);
        const replyOptions = MessageActions.getSendMessageOptionsForReply(
            PendingReplyStore.getPendingReply(channel.id),
        ) ?? {};

        await sendMessage(
            channel.id,
            { content: "" },
            false,
            { ...replyOptions, attachmentsToUpload: [upload] },
        );

        FluxDispatcher.dispatch({
            type: "DELETE_PENDING_REPLY",
            channelId: channel.id,
        });
    } finally {
        activeChannelUploads.delete(channel.id);
    }
}
