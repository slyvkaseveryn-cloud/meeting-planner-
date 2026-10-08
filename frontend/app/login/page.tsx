import { LoginRedirect } from "@/components/login-redirect";

export const metadata = {
  title: "Log in — SuccessfulSuccess",
};

/** The URL we hand out: it starts the sign-in in the app (state + PKCE), then goes to Cognito. */
export default function LoginPage() {
  return <LoginRedirect />;
}
