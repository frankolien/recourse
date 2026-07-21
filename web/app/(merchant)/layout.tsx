import { MerchantShell } from "@/components/merchant-shell";
import { Providers } from "@/components/providers";

export default function MerchantLayout({ children }: { children: React.ReactNode }) {
  return (
    <Providers>
      <MerchantShell>{children}</MerchantShell>
    </Providers>
  );
}
