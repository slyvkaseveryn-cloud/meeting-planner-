"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { signInWithRedirect } from "aws-amplify/auth";

import { AuthLoading } from "@/components/require-auth";
import { authErrorMessage, configureAuth } from "@/lib/auth";

/** Sends the browser to Cognito's managed login (email + password and Continue with Google). */
export function LoginRedirect() {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    configureAuth();
    signInWithRedirect().catch((caught: unknown) => {
      if (
        caught instanceof Error &&
        caught.name === "UserAlreadyAuthenticatedException"
      ) {
        router.replace("/today");
        return;
      }
      setError(authErrorMessage(caught));
    });
  }, [router]);

  if (error) {
    return (
      <p className="p-8 text-center text-sm text-red-600">
        Sign-in failed: {error}
      </p>
    );
  }
  return <AuthLoading label="Redirecting to sign in…" />;
}
