/*
 * Vencord, a Discord client mod
 * Copyright (c) 2026 Vendicated and contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import { Logger } from "@utils/Logger";
import type { RenderModalProps, SoundboardSound } from "@vencord/discord-types";
import {
    Modal,
    openModal,
    showToast,
    Toasts,
    useEffect,
    useRef,
    useState,
} from "@webpack/common";

import type { RandomSoundboardAction } from "./expressionPicker";
import { soundboardSourceName } from "./favoritePreview";
import { localize } from "./localization";
import {
    drawRandomSoundboard,
    playSoundboardSelection,
    resolveSoundboardPreviewUrl,
} from "./soundboardIntegration";
import { soundboardCandidateKey } from "./soundboardPool";

const logger = new Logger("RandomFavorites");

function pauseSoundboardPreview(audio?: HTMLAudioElement | null) {
    if (!audio) return;

    audio.pause();
    audio.currentTime = 0;
}

function RandomSoundboardPreviewModal({
    initialSound,
    modalProps,
}: {
    initialSound: SoundboardSound;
    modalProps: RenderModalProps;
}) {
    const [sound, setSound] = useState(initialSound);
    const [isSending, setIsSending] = useState(false);
    const [hasPreviewStarted, setHasPreviewStarted] = useState(false);
    const [previewUnavailable, setPreviewUnavailable] = useState(false);
    const audioRef = useRef<HTMLAudioElement>(null);
    let soundUrl: string | undefined;

    try {
        soundUrl = resolveSoundboardPreviewUrl(sound);
    } catch (error) {
        logger.error("Failed to resolve a soundboard preview URL", error);
    }

    useEffect(() => {
        setHasPreviewStarted(false);
        setPreviewUnavailable(false);

        const audio = audioRef.current;
        if (!audio || !soundUrl) return;

        audio.volume = Math.max(0, Math.min(sound.volume ?? 1, 1));
        void audio.play().catch(() => {
            // Autoplay can be denied. The native audio controls remain usable.
        });

        return () => pauseSoundboardPreview(audio);
    }, [sound.guildId, sound.soundId, sound.volume, soundUrl]);

    function reroll() {
        const draw = drawRandomSoundboard();
        if (draw.error) {
            showToast(draw.error, Toasts.Type.FAILURE);
            return;
        }

        if (draw.sound) {
            pauseSoundboardPreview(audioRef.current);
            setSound(draw.sound);
        }
    }

    function confirmPlay() {
        if (!hasPreviewStarted || previewUnavailable || !soundUrl) {
            showToast(localize(
                "Listen to the local preview before confirming.",
                "Écoute l'aperçu local avant de confirmer.",
            ), Toasts.Type.FAILURE);
            return;
        }

        setIsSending(true);
        pauseSoundboardPreview(audioRef.current);

        if (playSoundboardSelection(sound)) {
            modalProps.onClose();
        } else {
            setIsSending(false);
        }
    }

    return (
        <Modal
            {...modalProps}
            title={localize(
                "Safe random soundboard preview",
                "Aperçu soundboard aléatoire sécurisé",
            )}
            subtitle={localize(
                "This preview is local. Nothing plays in voice until you confirm.",
                "Cet aperçu est local. Rien ne passe dans le vocal avant ta confirmation.",
            )}
            actions={[
                {
                    text: localize("Cancel", "Annuler"),
                    variant: "secondary",
                    disabled: isSending,
                    onClick: modalProps.onClose,
                },
                {
                    text: localize("Draw again", "Relancer"),
                    variant: "secondary",
                    disabled: isSending,
                    onClick: reroll,
                },
                {
                    text: isSending
                        ? localize("Playing…", "Lecture…")
                        : hasPreviewStarted
                            ? localize("Play in voice", "Jouer dans le vocal")
                            : localize("Listen first", "Écoute d'abord"),
                    variant: "primary",
                    disabled: isSending
                        || !hasPreviewStarted
                        || previewUnavailable
                        || !soundUrl,
                    onClick: confirmPlay,
                },
            ]}
        >
            <div className="vc-rf-soundboard-preview">
                <div className="vc-rf-soundboard-preview-heading">
                    <span className="vc-rf-soundboard-preview-emoji" aria-hidden="true">
                        {sound.emojiName || "♪"}
                    </span>
                    <div>
                        <strong>{sound.name}</strong>
                        <span>{soundboardSourceName(sound.guildId)}</span>
                    </div>
                </div>
                {soundUrl ? (
                    <audio
                        key={soundboardCandidateKey(sound)}
                        ref={audioRef}
                        className="vc-rf-soundboard-audio"
                        src={soundUrl}
                        controls
                        preload="auto"
                        aria-label={localize(
                            `Private preview of ${sound.name}`,
                            `Aperçu privé de ${sound.name}`,
                        )}
                        onPlay={() => setHasPreviewStarted(true)}
                        onError={() => {
                            setHasPreviewStarted(false);
                            setPreviewUnavailable(true);
                        }}
                    />
                ) : null}
                {(previewUnavailable || !soundUrl) && (
                    <p className="vc-rf-soundboard-preview-error">
                        {localize(
                            "The local audio preview is unavailable. Draw again before confirming.",
                            "L'aperçu audio local est indisponible. Relance le tirage avant de confirmer.",
                        )}
                    </p>
                )}
            </div>
            <p className="vc-rf-preview-hint">
                {localize(
                    "Draw again only changes the private preview. The blue button is the only action that plays a sound in voice.",
                    "Relancer change uniquement l'aperçu privé. Seul le bouton bleu joue le son dans le vocal.",
                )}
            </p>
        </Modal>
    );
}

export function runRandomSoundboard(action: RandomSoundboardAction) {
    const draw = drawRandomSoundboard();
    if (draw.error || !draw.sound) {
        showToast(draw.error ?? localize(
            "No random sound could be selected.",
            "Aucun son aléatoire n'a pu être sélectionné.",
        ), Toasts.Type.FAILURE);
        return;
    }

    const initialSound = draw.sound;
    if (action === "direct") {
        playSoundboardSelection(initialSound);
        return;
    }

    openModal(modalProps => (
        <RandomSoundboardPreviewModal
            initialSound={initialSound}
            modalProps={modalProps}
        />
    ));
}
