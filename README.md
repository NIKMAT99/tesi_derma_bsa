# DermaBSA 

**DermaBSA** è un'applicazione mobile sviluppata in Flutter per il calcolo preciso e intuitivo della **Body Surface Area (BSA)** affetta da lesioni psoriasiche.

Nata come progetto di tesi di laurea in Informatica presso l'Università dell'Insubria, l'applicazione digitalizza e ottimizza il processo di mappatura dermatologica, sostituendo i calcoli forfettari manuali con un'interfaccia visiva interattiva ad altissima precisione.

##  Scopo del Progetto

Il calcolo della BSA è fondamentale in dermatologia per valutare la gravità della psoriasi e determinare i percorsi terapeutici (es. calcolo dell'indice PASI). DermaBSA permette a medici e pazienti di evidenziare visivamente le aree interessate direttamente su un modello anatomico digitale, calcolando matematicamente la percentuale di superficie corporea coinvolta tramite un'analisi "pixel-perfect".

##  Funzionalità Principali

* **Mappatura Interattiva (Fronte/Retro):** Un modello anatomico completo suddiviso in distretti ad alta granularità (es. braccio diviso in braccio superiore, avambraccio e mano).
* **Pittura a Mano Libera (Masking Avanzato):** L'utente può "colorare" le lesioni direttamente sull'area interessata. Grazie all'uso di `ShaderMask` e algoritmi di mascheratura su file PNG, il colore aderisce solo ai pixel reali dell'anatomia, impedendo sbavature sullo sfondo.
* **Strumenti di Precisione:** Possibilità di regolare lo spessore del pennello e utilizzare uno strumento "Gomma" basato su `BlendMode.clear` per correggere i dettagli della selezione.
* **Calcolo Algoritmico della BSA:** L'applicazione legge nativamente i byte (rawRgba) delle immagini per contare i pixel anatomici esatti e li confronta con l'area dipinta, garantendo un calcolo della percentuale molto più accurato rispetto alle stime visive.
* **Tutorial di Onboarding (Multistep):** Un sistema di overlay dinamico che guida i nuovi utenti alla scoperta dell'interfaccia, forzando le interazioni didattiche (es. obbligando il tocco su specifiche hitbox anatomiche).
* **Integrazione AI (Roadmap):** Predisposizione per l'integrazione di modelli di intelligenza artificiale per l'analisi e il riconoscimento automatico delle lesioni dermatologiche.

##  Tecnologie Utilizzate

* **Framework:** [Flutter](https://flutter.dev/) (Dart)
* **State Management:** Provider
* **Persistenza Dati:** SharedPreferences (per il tracciamento dei tutorial di Onboarding)
* **Grafica Nativa:** CustomPainter, Canvas API, ByteData manipulation

##  Struttura del Progetto

Le componenti centrali dell'applicazione sono organizzate come segue:

* `lib/ui/screens/interactive_mapper_screen.dart`: Cuore della mappatura. Gestisce il modello umano, le hitbox invisibili e il calcolo della BSA totale in tempo reale.
* `lib/ui/screens/region_painter_screen.dart`: Schermata di disegno (close-up). Gestisce il canvas, i pennelli, i livelli grafici e l'algoritmo di estrazione dei pixel.
* `lib/ui/widgets/tutorial_overlay.dart`: Componente custom per i pop-up di onboarding con effetto "buco trasparente" (punch-hole) per mettere in risalto elementi specifici della UI.
* `lib/models/body_region.dart`: Enum con la definizione precisa di tutte le parti del corpo e i relativi pesi percentuali standardizzati.
* `assets/images/`: Contiene tutte le sagome anatomiche (fronte, retro) e i file PNG ritagliati per le singole maschere di pittura.

##  Come avviare il progetto

### Prerequisiti
* [Flutter SDK](https://docs.flutter.dev/get-started/install) installato e configurato (versione 3.0+ consigliata).
* Emulatore Android/iOS funzionante o dispositivo fisico collegato.
* Android Studio o VS Code.

### Installazione

1. Clona il repository:
   ```bash
   git clone [https://github.com/tuo-username/DermaBSA.git](https://github.com/tuo-username/DermaBSA.git)