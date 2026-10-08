"use client";

import { Brand } from "./brand";

export function HeaderWeb({
  onNavigate,
  onLoginClick,
  isLoggedIn,
  currentTab,
}: {
  onNavigate: (tab: string) => void;
  onLoginClick: () => void;
  isLoggedIn: boolean;
  currentTab: string;
}) {
  return (
    <header className="w-full bg-white shadow-sm">
      {/* Top Utility Bar */}
      <div className="bg-[#0b3c74] text-white text-xs py-2 px-4 md:px-8 flex justify-between items-center">
        <div className="flex gap-4">
          <span className="flex items-center gap-1">
            <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" /><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" /></svg>
            Parakou - Cotonou et partout au Bénin
          </span>
          <span className="hidden lg:flex items-center gap-1">
            <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" /></svg>
            contact@axis.bj
          </span>
        </div>
        <div className="flex items-center gap-4">
          <span className="hidden sm:block opacity-90">Voyagez en toute confiance</span>
          <div className="flex gap-2 opacity-80">
            {/* Social Icons Placeholders */}
            <span className="font-bold">f</span>
            <span className="font-bold">X</span>
          </div>
        </div>
      </div>

      {/* Main Navigation Bar */}
      <div className="container mx-auto px-4 md:px-8 py-4 flex items-center justify-between">
        {/* Logo */}
        <div className="flex-shrink-0 cursor-pointer" onClick={() => onNavigate("accueil")}>
          <Brand />
        </div>

        {/* Desktop Nav Links */}
        <nav className="hidden lg:flex items-center gap-8 font-semibold text-[15px] text-[#0b3c74]">
          <button onClick={() => onNavigate("accueil")} className={currentTab === "accueil" ? "text-[#f9a826] border-b-2 border-[#f9a826] pb-1" : "hover:text-[#f9a826]"}>Accueil</button>
          <button onClick={() => onNavigate("billets")} className={currentTab === "billets" ? "text-[#f9a826] border-b-2 border-[#f9a826] pb-1" : "hover:text-[#f9a826]"}>Billets</button>
          <button onClick={() => onNavigate("colis")} className={currentTab === "colis" ? "text-[#f9a826] border-b-2 border-[#f9a826] pb-1" : "hover:text-[#f9a826]"}>Colis</button>
          <button onClick={() => onNavigate("location")} className={currentTab === "location" ? "text-[#f9a826] border-b-2 border-[#f9a826] pb-1" : "hover:text-[#f9a826]"}>Location</button>
          <button onClick={() => onNavigate("profil")} className="hover:text-[#f9a826]">Assistance</button>
          <button onClick={() => onNavigate("profil")} className="hover:text-[#f9a826]">À propos</button>
        </nav>

        {/* Action Buttons */}
        <div className="flex items-center gap-4">
          <button
            onClick={onLoginClick}
            className="hidden md:flex items-center gap-2 font-semibold text-[#0b3c74] hover:text-[#f9a826]"
          >
            <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" /></svg>
            {isLoggedIn ? "Mon compte" : "Se connecter"}
          </button>
          <button
            onClick={() => onNavigate("billets")}
            className="bg-[#f9a826] text-[#0b3c74] font-bold px-6 py-2.5 rounded-lg flex items-center gap-2 hover:bg-yellow-400 transition-colors shadow-sm"
          >
            <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" /></svg>
            Réserver
          </button>
        </div>
      </div>
    </header>
  );
}
