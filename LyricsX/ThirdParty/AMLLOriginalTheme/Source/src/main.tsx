import "@applemusic-like-lyrics/core/style.css";
import { BackgroundRender, LyricPlayer } from "@applemusic-like-lyrics/react";
import type { LyricLine } from "@applemusic-like-lyrics/core";
import React, { useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import "./styles.css";

declare global {
  interface Window {
    AMLLHost?: {
      setLyrics: (lines: LyricLine[]) => void;
      setCurrentTime: (timeMS: number) => void;
      setAlbum: (album: string | null) => void;
      setPlaying: (playing: boolean) => void;
      setVisualOptions: (options: VisualOptions) => void;
    };
  }
}

type VisualOptions = {
  alignment: "left" | "center";
  lineSpacing: number;
  motionAmount: number;
  fontFamily: string;
  fontSize: number;
};

const defaultFontFamily = '-apple-system, BlinkMacSystemFont, "SF Pro Display", "PingFang SC", sans-serif';

function postHostLog(message: string) {
    window.webkit?.messageHandlers?.amllLog?.postMessage?.(message);
}

window.addEventListener("error", (event) => {
  postHostLog(`error: ${event.message}`);
});

window.addEventListener("unhandledrejection", (event) => {
  postHostLog(`unhandledrejection: ${String(event.reason)}`);
});

type HostState = {
  lyricLines: LyricLine[];
  currentTime: number;
  album: string | null;
  playing: boolean;
  visualOptions: VisualOptions;
};

const hostState: HostState = {
  lyricLines: [],
  currentTime: 0,
  album: null,
  playing: true,
  visualOptions: {
    alignment: "left",
    lineSpacing: 1,
    motionAmount: 1,
    fontFamily: defaultFontFamily,
    fontSize: 32
  }
};

const hostSubscribers = new Set<() => void>();

function notifyHostSubscribers() {
  hostSubscribers.forEach((subscriber) => subscriber());
}

window.AMLLHost = {
  setLyrics: (lines) => {
    hostState.lyricLines = Array.isArray(lines) ? lines : [];
    postHostLog(`setLyrics lines=${hostState.lyricLines.length}`);
    notifyHostSubscribers();
  },
  setCurrentTime: (timeMS) => {
    hostState.currentTime = Number.isFinite(timeMS) ? Math.max(0, Math.round(timeMS)) : 0;
    notifyHostSubscribers();
  },
  setAlbum: (nextAlbum) => {
    hostState.album = nextAlbum;
    postHostLog(`setAlbum hasAlbum=${nextAlbum !== null}`);
    notifyHostSubscribers();
  },
  setPlaying: (playing) => {
    hostState.playing = playing;
    notifyHostSubscribers();
  },
  setVisualOptions: (options) => {
    hostState.visualOptions = {
      alignment: options?.alignment === "center" ? "center" : "left",
      lineSpacing: Number.isFinite(options?.lineSpacing) ? Math.min(1.6, Math.max(0.7, options.lineSpacing)) : 1,
      motionAmount: Number.isFinite(options?.motionAmount) ? Math.min(1.5, Math.max(0, options.motionAmount)) : 1,
      fontFamily: typeof options?.fontFamily === "string" && options.fontFamily.trim().length > 0
        ? options.fontFamily
        : defaultFontFamily,
      fontSize: Number.isFinite(options?.fontSize) ? Math.min(96, Math.max(12, options.fontSize)) : 32
    };
    postHostLog(`setVisualOptions align=${hostState.visualOptions.alignment} line=${hostState.visualOptions.lineSpacing} motion=${hostState.visualOptions.motionAmount} font=${hostState.visualOptions.fontFamily} size=${hostState.visualOptions.fontSize}`);
    notifyHostSubscribers();
  }
};

function AMLLOriginalTheme() {
  const [state, setState] = useState<HostState>(() => ({ ...hostState }));

  useEffect(() => {
    const syncState = () => setState({ ...hostState });
    hostSubscribers.add(syncState);
    syncState();
    return () => {
      hostSubscribers.delete(syncState);
    };
  }, []);

  const optimizeOptions = useMemo(
    () => ({
      normalizeSpaces: true,
      resetLineTimestamps: false,
      cleanUnintentionalOverlaps: true,
      tryAdvanceStartTime: true
    }),
    []
  );

  const motion = state.visualOptions.motionAmount;
  const playerStyle = {
    "--amll-line-spacing-scale": String(state.visualOptions.lineSpacing),
    "--amll-lp-font-size": `${state.visualOptions.fontSize}px`,
    "--amll-font-family": state.visualOptions.fontFamily,
    fontFamily: state.visualOptions.fontFamily
  } as React.CSSProperties;

  return (
    <main className="amll-root" data-align={state.visualOptions.alignment}>
      <BackgroundRender className="amll-bg" album={state.album ?? undefined} albumIsVideo={false} />
      <div className="amll-shade" />
      {state.lyricLines.length === 0 ? <div className="amll-empty">No lyrics</div> : null}
      <LyricPlayer
        className="amll-player"
        style={playerStyle}
        alignAnchor="center"
        alignPosition={0.48}
        enableBlur={motion > 0.1}
        enableScale={motion > 0.25}
        enableSpring={motion > 0.45}
        hidePassedLines={false}
        lyricLines={state.lyricLines}
        currentTime={state.currentTime}
        playing={state.playing}
        wordFadeWidth={motion <= 0.05 ? 0.0001 : 0.25 + 0.35 * motion}
        optimizeOptions={optimizeOptions}
      />
    </main>
  );
}

const rootElement = document.getElementById("root")!;
createRoot(rootElement, {
  onUncaughtError: (error) => {
    const message = error instanceof Error ? error.message : String(error);
    postHostLog(`react error: ${message}`);
    rootElement.innerHTML = `<div class="amll-empty">AMLL React error: ${message}</div>`;
  }
}).render(<AMLLOriginalTheme />);
requestAnimationFrame(() => {
  postHostLog("ready");
  window.webkit?.messageHandlers?.amllReady?.postMessage?.("ready");
});
