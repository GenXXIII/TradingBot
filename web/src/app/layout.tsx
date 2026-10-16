import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "AutoScalper Control",
  description: "Deterministic MT5 auto-trading control plane",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
