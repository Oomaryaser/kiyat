"use client";

import { FormEvent, useState } from "react";
import { LayoutDashboard, Loader2, LogIn, Phone, ShieldCheck } from "lucide-react";
import { ApiError, sendOperatorOtp, verifyOperatorOtp, type AuthTokens } from "@/lib/api";

interface LoginCardProps {
  onAuthenticated: (tokens: AuthTokens) => void;
  onDemoLogin: () => void;
}

export function LoginCard({ onAuthenticated, onDemoLogin }: LoginCardProps) {
  const [phone, setPhone] = useState("07701234567");
  const [otp, setOtp] = useState("");
  const [otpSent, setOtpSent] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSendOtp(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    setIsSubmitting(true);

    try {
      await sendOperatorOtp(phone.trim());
      setOtpSent(true);
    } catch (caught) {
      setError(readError(caught));
    } finally {
      setIsSubmitting(false);
    }
  }

  async function handleVerifyOtp(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    setIsSubmitting(true);

    try {
      const tokens = await verifyOperatorOtp(phone.trim(), otp.trim());
      onAuthenticated(tokens);
    } catch (caught) {
      setError(readError(caught));
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <main className="login-page">
      <section className="login-panel" aria-labelledby="login-title">
        <div className="brand-lockup">
          <img className="brand-mark" src="/kiyat-mark.svg" alt="" />
          <div>
            <p className="eyebrow">KIYAT ADMIN</p>
            <h1 id="login-title">لوحة كيات</h1>
          </div>
        </div>

        <form
          className="login-form"
          onSubmit={otpSent ? handleVerifyOtp : handleSendOtp}
        >
          <label className="field">
            <span>رقم الهاتف</span>
            <span className="input-wrap">
              <Phone aria-hidden="true" size={18} />
              <input
                inputMode="tel"
                dir="ltr"
                value={phone}
                onChange={(event) => setPhone(event.target.value)}
                placeholder="07701234567"
                required
              />
            </span>
          </label>

          {otpSent ? (
            <label className="field">
              <span>رمز التحقق</span>
              <span className="input-wrap">
                <ShieldCheck aria-hidden="true" size={18} />
                <input
                  inputMode="numeric"
                  dir="ltr"
                  value={otp}
                  onChange={(event) => setOtp(event.target.value)}
                  placeholder="123456"
                  required
                />
              </span>
            </label>
          ) : null}

          {error ? <p className="form-error">{error}</p> : null}

          <button className="primary-button" type="submit" disabled={isSubmitting}>
            {isSubmitting ? (
              <Loader2 aria-hidden="true" className="spin" size={18} />
            ) : otpSent ? (
              <LogIn aria-hidden="true" size={18} />
            ) : (
              <ShieldCheck aria-hidden="true" size={18} />
            )}
            <span>{otpSent ? "دخول" : "إرسال الرمز"}</span>
          </button>

          <button
            className="demo-button"
            type="button"
            disabled={isSubmitting}
            onClick={() => {
              setError(null);
              onDemoLogin();
            }}
          >
            <LayoutDashboard aria-hidden="true" size={18} />
            <span>دخول تجريبي بدون رمز</span>
          </button>

          {otpSent ? (
            <button
              className="ghost-button"
              type="button"
              disabled={isSubmitting}
              onClick={() => {
                setOtp("");
                setOtpSent(false);
                setError(null);
              }}
            >
              تغيير الرقم
            </button>
          ) : null}
        </form>
      </section>
    </main>
  );
}

function readError(caught: unknown) {
  if (caught instanceof ApiError) return caught.message;
  if (caught instanceof Error) return caught.message;
  return "حدث خطأ غير متوقع";
}
