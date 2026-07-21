import type { NextConfig } from "next";
import path from "node:path";

const nextConfig: NextConfig = {
  outputFileTracingRoot: path.join(process.cwd(), ".."),
  transpilePackages: ["@recourse/engine"],
  webpack: (config, { webpack }) => {
    // wagmi's bundled connectors (Coinbase, MetaMask, WalletConnect) reference
    // optional packages we neither install nor use (we only use the injected
    // connector): @x402/* via @coinbase/cdp-sdk, React Native async storage via
    // @metamask/sdk, and pino-pretty via WalletConnect logging. Ignore them.
    config.plugins.push(
      new webpack.IgnorePlugin({
        resourceRegExp: /^(@x402\/|pino-pretty$|@react-native-async-storage\/async-storage$)/,
      }),
    );
    return config;
  },
};

export default nextConfig;
