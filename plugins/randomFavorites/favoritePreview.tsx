/*
 * Vencord, a Discord client mod
 * Copyright (c) 2026 Vendicated and contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import { findByPropsLazy } from "@webpack";
import {
    GuildStore,
    Parser,
    useEffect,
    useRef,
    useState,
} from "@webpack/common";

import { RandomFavoritesIcon } from "./icons";
import { localize } from "./localization";
import { resolveSoundboardPreviewUrl } from "./soundboardIntegration";
import type { ConcreteFavoriteKind, FavoriteCandidate } from "./types";

const LottiePlayer = findByPropsLazy("loadAnimation") as {
    loadAnimation(options: {
        autoplay: boolean;
        container: HTMLElement;
        loop: boolean;
        path: string;
        renderer: "svg";
    }): { destroy(): void; };
};

function previewKindLabel(kind: ConcreteFavoriteKind) {
    const labels: Record<ConcreteFavoriteKind, [string, string]> = {
        gif: ["Random GIF", "GIF aléatoire"],
        emoji: ["Random emoji", "Emote aléatoire"],
        sticker: ["Random sticker", "Sticker aléatoire"],
        soundboard: ["Random soundboard sound", "Son aléatoire"],
    };

    return localize(...labels[kind]);
}

function LottieStickerPreview({ label, url }: { label: string; url: string; }) {
    const containerRef = useRef<HTMLDivElement>(null);

    useEffect(() => {
        if (!containerRef.current) return;

        const animation = LottiePlayer.loadAnimation({
            autoplay: true,
            container: containerRef.current,
            loop: true,
            path: url,
            renderer: "svg",
        });

        return () => animation.destroy();
    }, [url]);

    return (
        <div
            ref={containerRef}
            role="img"
            aria-label={label}
            className="vc-rf-preview-lottie"
        />
    );
}

function pauseAudioPreview(audio?: HTMLAudioElement | null) {
    if (!audio) return;

    audio.pause();
    audio.currentTime = 0;
}

function SoundboardAudioPreview({ candidate }: { candidate: FavoriteCandidate; }) {
    const audioRef = useRef<HTMLAudioElement>(null);
    const [previewUnavailable, setPreviewUnavailable] = useState(false);
    const snapshot = candidate.soundboard;
    const soundUrl = snapshot
        ? candidate.previewUrl ?? resolveSoundboardPreviewUrl(snapshot)
        : undefined;

    useEffect(() => {
        setPreviewUnavailable(false);

        const audio = audioRef.current;
        if (!audio || !soundUrl || !snapshot) return;

        audio.volume = snapshot.volume;
        void audio.play().catch(() => {
            // Autoplay can be denied without making the controls unusable.
        });

        return () => pauseAudioPreview(audio);
    }, [candidate.key, snapshot?.volume, soundUrl]);

    if (!snapshot || !soundUrl) {
        return (
            <div className="vc-rf-preview-fallback">
                <RandomFavoritesIcon height={44} width={44} />
                <span>{localize("Audio preview unavailable", "Aperçu audio indisponible")}</span>
            </div>
        );
    }

    return (
        <div className="vc-rf-preview-audio">
            <span className="vc-rf-preview-audio-icon" aria-hidden="true">
                {snapshot.emojiName || "🔊"}
            </span>
            <audio
                key={candidate.key}
                ref={audioRef}
                className="vc-rf-preview-audio-controls"
                src={soundUrl}
                controls
                autoPlay
                preload="metadata"
                aria-label={candidate.label}
                onError={() => setPreviewUnavailable(true)}
            />
            {previewUnavailable && (
                <span className="vc-rf-preview-audio-error">
                    {localize(
                        "The local audio preview is unavailable.",
                        "L'aperçu audio local est indisponible.",
                    )}
                </span>
            )}
        </div>
    );
}

function FavoriteMediaPreview({ candidate }: { candidate: FavoriteCandidate; }) {
    if (candidate.kind === "soundboard")
        return <SoundboardAudioPreview candidate={candidate} />;

    const fallbackSource = candidate.previewUrl
        ? [{ type: candidate.previewType ?? "image", url: candidate.previewUrl } as const]
        : [];
    const sources = candidate.previewSources ?? fallbackSource;
    const [sourceIndex, setSourceIndex] = useState(0);
    const source = sources[sourceIndex];

    useEffect(() => setSourceIndex(0), [candidate.key]);

    if (source?.type === "lottie")
        return <LottieStickerPreview label={candidate.label} url={source.url} />;

    if (source?.type === "video") {
        return (
            <video
                src={source.url}
                aria-label={candidate.label}
                className="vc-rf-preview-image"
                autoPlay
                loop
                muted
                playsInline
                onError={() => setSourceIndex(index => index + 1)}
            />
        );
    }

    if (source) {
        return (
            <img
                src={source.url}
                alt={candidate.label}
                className="vc-rf-preview-image"
                onError={() => setSourceIndex(index => index + 1)}
            />
        );
    }

    if (candidate.kind === "emoji" && candidate.content) {
        return (
            <div className="vc-rf-preview-emoji">
                {Parser.parse(candidate.content)}
            </div>
        );
    }

    return (
        <div className="vc-rf-preview-fallback">
            <RandomFavoritesIcon height={44} width={44} />
            <span>{localize("Preview unavailable", "Aperçu indisponible")}</span>
        </div>
    );
}

export function soundboardSourceName(guildId: string | null | undefined) {
    if (!guildId || guildId === "0")
        return localize("Discord sounds", "Sons Discord");

    return GuildStore.getGuild(guildId)?.name
        ?? localize("Unknown server", "Serveur inconnu");
}

export function FavoritePreviewCard({ candidate }: { candidate: FavoriteCandidate; }) {
    const sourceName = candidate.soundboard
        ? soundboardSourceName(candidate.soundboard.guildId)
        : undefined;

    return (
        <article className="vc-rf-preview-card">
            <div className="vc-rf-preview-media">
                <FavoriteMediaPreview candidate={candidate} />
            </div>
            <div className="vc-rf-preview-meta">
                <strong>{previewKindLabel(candidate.kind)}</strong>
                <span title={candidate.label}>{candidate.label}</span>
                {sourceName && <span title={sourceName}>{sourceName}</span>}
            </div>
        </article>
    );
}
