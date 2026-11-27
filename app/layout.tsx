import type { Metadata, Viewport } from "next";
import "./globals.css";
import { ServiceWorkerRegister } from "./sw-register";
export const metadata: Metadata = { title: "KARDEN — The Private Card Club", description: "A private table. Your people. One more round.", applicationName: "KARDEN", manifest: "/manifest.json", appleWebApp: { capable: true, statusBarStyle: "black-translucent", title: "KARDEN" } };
export const viewport: Viewport = { themeColor: "#090b0a", width: "device-width", initialScale: 1, maximumScale: 1 };
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) { return <html lang="en"><body><ServiceWorkerRegister/>{children}</body></html>; }
