import { MerchantShell } from "@/components/merchant-shell";

export default function MerchantLayout({ children }: { children: React.ReactNode }) {
  return <MerchantShell>{children}</MerchantShell>;
}
