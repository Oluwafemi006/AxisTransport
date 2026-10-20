import { FormEvent } from "react";

export interface ActivationFormProps {
  email?: string;
  group?: string;
  roleLabel?: string;
  password?: string;
  confirmPassword?: string;
  submitting?: boolean;
  submitError?: string | null;
  onPasswordChange?: (value: string) => void;
  onConfirmPasswordChange?: (value: string) => void;
  onSubmit?: (event: FormEvent) => void;
}

export function ActivationForm({
  email,
  group,
  roleLabel,
  password = "",
  confirmPassword = "",
  submitting = false,
  submitError = null,
  onPasswordChange,
  onConfirmPasswordChange,
  onSubmit,
}: ActivationFormProps) {
  return (
    <form onSubmit={onSubmit} data-testid="activation-form">
      <p className="eyebrow">Personnel AXIS</p>
      <h1 className="mt-2 text-2xl font-extrabold text-axis-900">
        Définissez votre mot de passe pour activer votre compte AXIS
      </h1>
      {email && (
        <div className="mt-3 rounded-lg bg-blue-50 border border-blue-200 p-3 text-xs text-blue-900">
          Compte : <strong>{email}</strong>
          {roleLabel && (
            <>
              <br />
              Rôle attribué : <strong>{roleLabel}</strong>{group ? ` (${group})` : ""}
            </>
          )}
        </div>
      )}

      <label className="field-label mt-5" htmlFor="password">
        Nouveau mot de passe
      </label>
      <input
        id="password"
        name="password"
        type="password"
        className="field"
        autoComplete="new-password"
        placeholder="8 caractères minimum"
        value={password}
        onChange={(e) => onPasswordChange?.(e.target.value)}
        required
        minLength={8}
      />

      <label className="field-label mt-4" htmlFor="confirmPassword">
        Confirmer le mot de passe
      </label>
      <input
        id="confirmPassword"
        name="confirmPassword"
        type="password"
        className="field"
        autoComplete="new-password"
        value={confirmPassword}
        onChange={(e) => onConfirmPasswordChange?.(e.target.value)}
        required
        minLength={8}
      />

      {submitError && (
        <p className="notice notice-error mt-4" role="alert">
          {submitError}
        </p>
      )}

      <button
        type="submit"
        className="primary-button mt-6 w-full"
        disabled={submitting}
      >
        {submitting ? "Activation en cours…" : "Activer mon compte"}
      </button>
    </form>
  );
}
