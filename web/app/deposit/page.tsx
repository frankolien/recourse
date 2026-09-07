import { Suspense } from "react";
import { BridgeDeposit } from "@/components/deposit/bridge";

export default function DepositPage() {
  return (
    <Suspense fallback={<div className="dep-wrap" />}>
      <BridgeDeposit />
    </Suspense>
  );
}
