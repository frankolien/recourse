"use client";

import type { AnimationItem } from "lottie-web";
import { useEffect, useRef } from "react";

interface LottiePlayerProps {
  animationData: unknown;
  loop?: boolean;
  autoplay?: boolean;
  className?: string;
}

/**
 * lottie-web is imported dynamically inside the effect because it touches the
 * DOM at module scope, which would break server rendering. The animation is
 * destroyed on unmount, and reduced-motion viewers get a static last frame.
 */
export function LottiePlayer({ animationData, loop = true, autoplay = true, className }: LottiePlayerProps) {
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    let animation: AnimationItem | undefined;
    let cancelled = false;
    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    void import("lottie-web").then((module) => {
      if (cancelled || !containerRef.current) return;
      animation = module.default.loadAnimation({
        container: containerRef.current,
        renderer: "svg",
        loop,
        autoplay: autoplay && !reduceMotion,
        animationData: animationData as Record<string, unknown>,
      });
      if (reduceMotion) {
        animation.goToAndStop(animation.totalFrames - 1, true);
      }
    });

    return () => {
      cancelled = true;
      animation?.destroy();
    };
  }, [animationData, loop, autoplay]);

  return <div ref={containerRef} className={className} aria-hidden="true" role="presentation" />;
}
