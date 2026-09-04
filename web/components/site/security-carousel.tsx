"use client";

import { useEffect, useId, useState, useSyncExternalStore } from "react";
import type { KeyboardEvent, ReactNode } from "react";
import { PhoneKeys } from "./phone";

function FaceIdGlyph() {
  return (
    <svg viewBox="0 0 64 64" width="104" height="104" fill="none" stroke="currentColor" strokeWidth="4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M8 22v-8a6 6 0 0 1 6-6h8" />
      <path d="M42 8h8a6 6 0 0 1 6 6v8" />
      <path d="M56 42v8a6 6 0 0 1-6 6h-8" />
      <path d="M22 56h-8a6 6 0 0 1-6-6v-8" />
      <path d="M22 25v7" />
      <path d="M42 25v7" />
      <path d="M32 25v11h-3" />
      <path d="M23 42a13 13 0 0 0 18 0" />
    </svg>
  );
}

function Shield() {
  return (
    <svg viewBox="0 0 96 112" width="132" height="154" aria-hidden="true">
      <defs>
        <linearGradient id="site-shield-fill" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#149a72" />
          <stop offset="1" stopColor="#064535" />
        </linearGradient>
      </defs>
      <path d="M48 4 8 20v30c0 26 17 46 40 54 23-8 40-28 40-54V20L48 4Z" fill="url(#site-shield-fill)" />
      <path d="M31 56l12 12 22-26" stroke="#fff" strokeWidth="7" fill="none" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

const slides: { title: string; text: string; visual: ReactNode }[] = [
  {
    title: "Two keys sign, one of them is yours",
    text: "Your phone's Secure Enclave and your iCloud key sign together. Neither leaves the device that holds it.",
    visual: (
      <span className="site-security-pair">
        <FaceIdGlyph />
        <span className="site-security-plus" aria-hidden="true">
          +
        </span>
        <span className="site-security-tile">2 of 3</span>
      </span>
    ),
  },
  {
    title: "Lose the phone, keep the money",
    text: "A sealed recovery key and your cloud key bring the account back on a new phone. Nothing to write down.",
    visual: <PhoneKeys />,
  },
  {
    title: "No single key we hold can spend",
    text: "The account is a 2-of-3 smart account on Arc. The chain enforces it, not us.",
    visual: <Shield />,
  },
];

const ROTATE_MS = 5000;
const REDUCED_MOTION = "(prefers-reduced-motion: reduce)";

function subscribe(onChange: () => void) {
  const query = window.matchMedia(REDUCED_MOTION);
  query.addEventListener("change", onChange);
  return () => query.removeEventListener("change", onChange);
}

function getSnapshot() {
  return window.matchMedia(REDUCED_MOTION).matches;
}

// Until the client hydrates, behave as if motion is reduced so nothing rotates
// before the user's preference has been read.
function getServerSnapshot() {
  return true;
}

export function SecurityCarousel() {
  const [index, setIndex] = useState(0);
  const reducedMotion = useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
  const baseId = useId();

  useEffect(() => {
    if (reducedMotion) return;
    const id = window.setInterval(() => {
      setIndex((current) => (current + 1) % slides.length);
    }, ROTATE_MS);
    return () => window.clearInterval(id);
  }, [reducedMotion, index]);

  function select(next: number) {
    const wrapped = (next + slides.length) % slides.length;
    setIndex(wrapped);
    document.getElementById(`${baseId}-tab-${wrapped}`)?.focus();
  }

  function onKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (event.key === "ArrowRight") select(index + 1);
    else if (event.key === "ArrowLeft") select(index - 1);
    else if (event.key === "Home") select(0);
    else if (event.key === "End") select(slides.length - 1);
    else return;
    event.preventDefault();
  }

  const slide = slides[index];

  return (
    <div className="site-split">
      <div className="site-panel site-security-panel">
        <div key={index} className="site-security-visual" aria-hidden={index !== 1}>
          {slide.visual}
        </div>
      </div>
      <div className="site-split-copy">
        <h2 id="security" className="site-h2">
          Bank-grade security that fits in your pocket
        </h2>
        <div className="site-carousel">
          <div className="site-carousel-bars" role="tablist" aria-label="How the account is secured" onKeyDown={onKeyDown}>
            {slides.map((item, i) => {
              const active = i === index;
              return (
                <button
                  key={item.title}
                  type="button"
                  role="tab"
                  id={`${baseId}-tab-${i}`}
                  aria-selected={active}
                  aria-controls={`${baseId}-panel`}
                  tabIndex={active ? 0 : -1}
                  className={active ? "site-carousel-bar is-active" : "site-carousel-bar"}
                  onClick={() => setIndex(i)}
                >
                  <span className="site-carousel-track">
                    <span className={reducedMotion ? "site-carousel-fill is-static" : "site-carousel-fill"} />
                  </span>
                  <span className="site-visually-hidden">{item.title}</span>
                </button>
              );
            })}
          </div>
          <div className="site-carousel-slide" role="tabpanel" id={`${baseId}-panel`} aria-labelledby={`${baseId}-tab-${index}`}>
            <h3 key={slide.title} className="site-h3">
              {slide.title}
            </h3>
            <p key={slide.text}>{slide.text}</p>
          </div>
        </div>
      </div>
    </div>
  );
}
