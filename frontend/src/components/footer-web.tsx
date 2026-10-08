"use client";

import { Brand } from "./brand";

export function FooterWeb() {
  return (
    <footer className="bg-[#0a2540] text-white pt-16 pb-8">
      <div className="container mx-auto px-4 md:px-8">
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-8 mb-12">
          {/* Brand Column */}
          <div className="lg:col-span-2">
            <div className="brightness-0 invert mb-4">
              <Brand />
            </div>
            <p className="text-sm text-slate-300 mt-4 max-w-sm leading-relaxed">
              Plus proches de vous, partout au Bénin. AXIS Transport est votre partenaire de confiance pour des voyages sûrs et confortables.
            </p>
          </div>

          {/* Navigation */}
          <div>
            <h4 className="font-bold mb-4 text-white">Navigation</h4>
            <ul className="space-y-3 text-sm text-slate-300">
              <li><a href="#" className="hover:text-[#f9a826]">Accueil</a></li>
              <li><a href="#" className="hover:text-[#f9a826]">Billets</a></li>
              <li><a href="#" className="hover:text-[#f9a826]">Colis</a></li>
              <li><a href="#" className="hover:text-[#f9a826]">Location</a></li>
              <li><a href="#" className="hover:text-[#f9a826]">Assistance</a></li>
            </ul>
          </div>

          {/* À propos */}
          <div>
            <h4 className="font-bold mb-4 text-white">À propos</h4>
            <ul className="space-y-3 text-sm text-slate-300">
              <li><a href="#" className="hover:text-[#f9a826]">Notre histoire</a></li>
              <li><a href="#" className="hover:text-[#f9a826]">Nos valeurs</a></li>
              <li><a href="#" className="hover:text-[#f9a826]">Nos agences</a></li>
              <li><a href="#" className="hover:text-[#f9a826]">Nous rejoindre</a></li>
            </ul>
          </div>

          {/* Assistance */}
          <div>
            <h4 className="font-bold mb-4 text-white">Assistance</h4>
            <ul className="space-y-3 text-sm text-slate-300">
              <li><a href="#" className="hover:text-[#f9a826]">FAQ</a></li>
              <li><a href="#" className="hover:text-[#f9a826]">Contact</a></li>
              <li><a href="#" className="hover:text-[#f9a826]">Suivi de colis</a></li>
              <li><a href="#" className="hover:text-[#f9a826]">Réclamation</a></li>
            </ul>
          </div>
        </div>

        {/* Bottom Footer */}
        <div className="border-t border-slate-700 pt-8 flex flex-col md:flex-row items-center justify-between gap-4">
          <p className="text-xs text-slate-400">
            © {new Date().getFullYear()} AXIS Transport. Tous droits réservés.
          </p>
          
          <div className="flex gap-4 text-xs text-slate-400">
            <a href="#" className="hover:text-white">Mentions légales</a>
            <span>|</span>
            <a href="#" className="hover:text-white">Politique de confidentialité</a>
          </div>

          {/* Socials */}
          <div className="flex gap-4">
            <div className="w-8 h-8 rounded-full bg-slate-800 flex items-center justify-center hover:bg-[#f9a826] cursor-pointer transition-colors">f</div>
            <div className="w-8 h-8 rounded-full bg-slate-800 flex items-center justify-center hover:bg-[#f9a826] cursor-pointer transition-colors">W</div>
            <div className="w-8 h-8 rounded-full bg-slate-800 flex items-center justify-center hover:bg-[#f9a826] cursor-pointer transition-colors">X</div>
            <div className="w-8 h-8 rounded-full bg-slate-800 flex items-center justify-center hover:bg-[#f9a826] cursor-pointer transition-colors">Y</div>
          </div>
        </div>
      </div>
    </footer>
  );
}
