"use client";

import { useEffect, useState } from "react";

export type RecourseRole = "buyer" | "merchant" | "liquidity";

export interface DemoProfile {
  firstName: string;
  lastName: string;
  email: string;
  role: RecourseRole;
  workspace: string;
  onboardingComplete: boolean;
}

const PROFILE_KEY = "recourse.demo-profile";

export const defaultDemoProfile: DemoProfile = {
  firstName: "Frank",
  lastName: "Olien",
  email: "frank@example.com",
  role: "merchant",
  workspace: "Acme Store",
  onboardingComplete: false,
};

export function readDemoProfile(): DemoProfile {
  if (typeof window === "undefined") return defaultDemoProfile;

  try {
    const stored = window.localStorage.getItem(PROFILE_KEY);
    return stored ? { ...defaultDemoProfile, ...JSON.parse(stored) } : defaultDemoProfile;
  } catch {
    return defaultDemoProfile;
  }
}

export function saveDemoProfile(profile: DemoProfile) {
  window.localStorage.setItem(PROFILE_KEY, JSON.stringify(profile));
  window.dispatchEvent(new Event("recourse-profile-change"));
}

export function useDemoProfile() {
  const [profile, setProfile] = useState(defaultDemoProfile);

  useEffect(() => {
    const syncProfile = () => setProfile(readDemoProfile());
    syncProfile();
    window.addEventListener("storage", syncProfile);
    window.addEventListener("recourse-profile-change", syncProfile);
    return () => {
      window.removeEventListener("storage", syncProfile);
      window.removeEventListener("recourse-profile-change", syncProfile);
    };
  }, []);

  return profile;
}
