"use client";

import { useState, type InputHTMLAttributes } from "react";

type PasswordInputProps = Omit<InputHTMLAttributes<HTMLInputElement>, "type"> & {
  // Classe du champ lui-même ; le conteneur ajoute la place du bouton à droite.
  className?: string;
};

// Champ de mot de passe avec bouton afficher/masquer. Masqué par défaut ; chaque champ a son propre bouton.
// Le bouton ne soumet jamais le formulaire (type="button") et garde id, name et autoComplete du champ,
// pour que le gestionnaire de mots de passe du navigateur continue de reconnaître le champ.
export function PasswordInput({ className = "field", style, ...props }: PasswordInputProps) {
  const [visible, setVisible] = useState(false);
  return (
    <div style={{ position: "relative" }}>
      <input {...props} type={visible ? "text" : "password"} className={className} style={{ ...style, paddingRight: 52 }} />
      <button
        type="button"
        onClick={() => setVisible((value) => !value)}
        aria-label={visible ? "Masquer le mot de passe" : "Afficher le mot de passe"}
        aria-pressed={visible}
        aria-controls={props.id}
        className="password-toggle"
        style={{
          position: "absolute", top: "50%", right: 2, transform: "translateY(-50%)",
          width: 44, height: 44, display: "grid", placeItems: "center",
          background: "transparent", border: 0, borderRadius: 8, cursor: "pointer", color: "#475569",
        }}
      >
        {visible ? (
          <svg aria-hidden="true" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M3 3l18 18" />
            <path d="M10.6 10.6a2 2 0 0 0 2.8 2.8" />
            <path d="M9.9 5.1A10.4 10.4 0 0 1 12 5c6.5 0 10 7 10 7a17.6 17.6 0 0 1-3.2 4.2M6.6 6.6C3.6 8.5 2 12 2 12s3.5 7 10 7a9.7 9.7 0 0 0 5.4-1.6" />
          </svg>
        ) : (
          <svg aria-hidden="true" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7Z" />
            <circle cx="12" cy="12" r="3" />
          </svg>
        )}
      </button>
    </div>
  );
}
