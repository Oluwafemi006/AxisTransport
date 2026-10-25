"use client";

import { FormEvent, useEffect, useState } from "react";
import Link from "next/link";
import { Brand } from "@/components/brand";
import { ActivationForm } from "@/components/activation-form";
import {
  acceptStaffInvitation,
  verifyStaffInvitation,
  type StaffInvitationAcceptResponse,
  type StaffInvitationVerification,
} from "@/lib/api";
import { activationPasswordError, staffPortalLoginUrl } from "@/lib/portal-rules";

export function ActivationCard({ token }: { token?: string | null }) {
  const [loading, setLoading] = useState(true);
  const [invitation, setInvitation] = useState<StaffInvitationVerification | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);

  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState<string | null>(null);
  const [success, setSuccess] = useState<StaffInvitationAcceptResponse | null>(null);

  useEffect(() => {
    if (!token) {
      setLoading(false);
      setLoadError("Jeton d'activation manquant. Veuillez utiliser le lien complet figurant dans l'e-mail reçu.");
      return;
    }

    let active = true;
    setLoading(true);
    setLoadError(null);

    verifyStaffInvitation(token)
      .then((data) => {
        if (!active) return;
        setInvitation(data);
      })
      .catch((reason: unknown) => {
        if (!active) return;
        const msg = reason instanceof Error ? reason.message : "Ce lien d'invitation est invalide ou a expiré.";
        setLoadError(msg);
      })
      .finally(() => {
        if (active) setLoading(false);
      });

    return () => {
      active = false;
    };
  }, [token]);

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    if (!token) return;

    setSubmitError(null);
    const clientErr = activationPasswordError(password, confirmPassword);
    if (clientErr) {
      setSubmitError(clientErr);
      return;
    }

    setSubmitting(true);
    try {
      const response = await acceptStaffInvitation(token, password);
      setSuccess(response);
    } catch (reason: unknown) {
      const msg = reason instanceof Error ? reason.message : "Impossible d'activer votre compte. Veuillez réessayer.";
      setSubmitError(msg);
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="login-card mx-auto max-w-md my-8">
      <div className="mb-6 flex justify-center">
        <Brand />
      </div>

      {loading && (
        <div className="text-center py-8">
          <p className="text-slate-600 font-medium">Vérification de l’invitation…</p>
        </div>
      )}

      {!loading && loadError && (
        <div>
          <p className="eyebrow text-red-600">Lien invalide ou expiré</p>
          <h1 className="mt-2 text-xl font-extrabold text-axis-900">Activation impossible</h1>
          <p className="notice notice-error mt-4" role="alert">{loadError}</p>
          <p className="mt-4 text-xs text-slate-500">
            Si votre invitation a expiré ou si vous l’avez déjà utilisée, demandez à votre administrateur de vous renvoyer une nouvelle invitation depuis l’administration.
          </p>
          <div className="mt-6 flex justify-center">
            <Link href="/" className="text-button text-sm">
              Retour à l’accueil
            </Link>
          </div>
        </div>
      )}

      {!loading && !loadError && success && (
        <div>
          <p className="eyebrow text-green-700">Compte activé</p>
          <h1 className="mt-2 text-2xl font-extrabold text-axis-900">Bienvenue sur AXIS</h1>
          <p className="notice notice-success mt-4">
            Votre compte pour <strong>{success.username}</strong> a été activé avec succès avec le rôle <strong>{success.group}</strong>.
          </p>

          <div className="mt-6">
            <Link
              href={staffPortalLoginUrl(success.role)}
              className="primary-button block w-full text-center"
            >
              Se connecter au portail {success.group}
            </Link>
          </div>

          <div className="mt-8 rounded-xl border border-slate-200 bg-slate-50 p-4">
            <p className="text-sm font-bold text-slate-800">📱 Application mobile AXIS Transport</p>
            <p className="mt-1 text-xs text-slate-600">
              Pour la vente de billets au guichet et le contrôle des passagers sur le terrain, installez l’application mobile Axis Transport.
            </p>
            <a
              href="https://play.google.com/store/apps/details?id=com.axis.transport"
              target="_blank"
              rel="noopener noreferrer"
              className="mt-3 inline-block text-xs font-semibold text-blue-600 hover:underline"
            >
              Disponible sur le Google Play Store →
            </a>
          </div>
        </div>
      )}

      {!loading && !loadError && !success && (
        <ActivationForm
          email={invitation?.email}
          group={invitation?.group}
          roleLabel={invitation?.role_label}
          password={password}
          confirmPassword={confirmPassword}
          submitting={submitting}
          submitError={submitError}
          onPasswordChange={setPassword}
          onConfirmPasswordChange={setConfirmPassword}
          onSubmit={handleSubmit}
        />
      )}
    </div>
  );
}
