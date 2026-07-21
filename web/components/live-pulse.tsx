import { ShieldCheck } from "lucide-react";
import { LottiePlayer } from "@/components/lottie-player";
import burstAnimation from "@/lib/lottie/burst.json";
import pingAnimation from "@/lib/lottie/ping.json";

export function LivePulse({ className = "" }: { className?: string }) {
  return <LottiePlayer animationData={pingAnimation} className={`live-pulse ${className}`} />;
}

export function ProtectionMark({ className = "" }: { className?: string }) {
  return (
    <span className={`protection-mark ${className}`}>
      <LottiePlayer animationData={burstAnimation} className="protection-mark-motion" />
      <span className="protection-mark-core"><ShieldCheck size={19} /></span>
    </span>
  );
}
