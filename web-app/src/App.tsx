import { useState } from 'react';
import { GlassContainer } from './components/layout/GlassContainer';
import { GlassCard } from './components/ui/GlassCard';
import { RiskForm } from './features/calculator/RiskForm';
import { ResultCard } from './features/results/ResultCard';
import { SHAPBarChart } from './components/viz/SHAPBarChart';
import { predictRisk } from './api/client';
import type { PatientData, PredictionResponse } from './api/client';
import { AnimatePresence, motion } from 'framer-motion';

// Safely extract scalar from potential R array (R sometimes wraps scalars in arrays)
const unwrapScalar = <T,>(value: T | T[]): T =>
    Array.isArray(value) ? value[0] : value;

// Validate API response has required fields
const isValidResponse = (res: unknown): res is PredictionResponse => {
    if (!res || typeof res !== 'object') return false;
    const r = res as Record<string, unknown>;
    return 'risk_score' in r && 'risk_percentage' in r &&
           'risk_level' in r && 'explanation' in r;
};

function App() {
  const [isLoading, setIsLoading] = useState(false);
  const [result, setResult] = useState<PredictionResponse | null>(null);
  const [error, setError] = useState<string | null>(null);

  const handleCalculate = async (data: PatientData) => {
    setIsLoading(true);
    setError(null);
    try {
      const response = await predictRisk(data);

      // Validate response structure
      if (!isValidResponse(response)) {
        throw new Error('Invalid API response structure');
      }

      // Normalize response (unwrap any R array-wrapped scalars)
      const normalized: PredictionResponse = {
        ...response,
        risk_score: unwrapScalar(response.risk_score),
        risk_percentage: unwrapScalar(response.risk_percentage),
        risk_level: unwrapScalar(response.risk_level),
      };

      setResult(normalized);
    } catch (err) {
      console.error(err);
      setError("Error al calcular riesgo. Asegúrese de que la API esté en funcionamiento.");
    } finally {
      setIsLoading(false);
    }
  };

  const handleReset = () => {
    setResult(null);
    setError(null);
  };

  return (
    <GlassContainer>
      <header className="mb-4 text-center">
        <GlassCard className="inline-block px-6 py-3 mb-2 !bg-white/80">
          <h1 className="text-3xl md:text-4xl font-extrabold bg-gradient-to-r from-slate-800 to-slate-600 bg-clip-text text-transparent">
            Riesgo de Mortalidad COVID-19
          </h1>
        </GlassCard>
        <p className="text-slate-600 text-base md:text-lg font-medium max-w-2xl mx-auto">
          Modelo predictivo de Machine Learning basado en datos clínicos de ingreso.
        </p>
      </header>

      <div className="relative">
        <AnimatePresence mode="wait">
          {!result ? (
            <motion.div
              key="form"
              initial={{ opacity: 0, x: -20 }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0, x: -20 }}
              transition={{ duration: 0.2 }}
            >
              <RiskForm onSubmit={handleCalculate} isLoading={isLoading} />
              {error && (
                <div className="mt-3 p-3 bg-red-100 text-red-700 rounded-xl text-center font-medium border border-red-200 text-sm">
                  {error}
                </div>
              )}
            </motion.div>
          ) : (
            <motion.div
              key="results"
              initial={{ opacity: 0, x: 20 }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0, x: 20 }}
              transition={{ duration: 0.2 }}
              className="grid gap-4 md:grid-cols-2 lg:grid-cols-3"
            >
              {/* Puntuación de Riesgo Principal */}
              <div className="md:col-span-1 lg:col-span-1 h-full">
                <ResultCard result={result} />
              </div>

              {/* Explicaciones (SHAP) */}
              <div className="md:col-span-1 lg:col-span-2 h-full">
                <SHAPBarChart data={result.explanation} />
              </div>

              {/* Botones de Acción */}
              <div className="md:col-span-2 lg:col-span-3 flex justify-center mt-2">
                <button
                  onClick={handleReset}
                  className="px-6 py-2 bg-white/50 hover:bg-white/80 text-slate-700 font-semibold rounded-xl border border-white/40 transition-all shadow-sm text-sm"
                >
                  Nueva Evaluación
                </button>
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </div>

      <footer className="mt-4 text-center text-slate-500 text-xs">
        <p>Solo para uso en investigación. No sustituye el consejo médico profesional.</p>
        <p className="mt-1 opacity-75">© 2026 Grupo de Investigación COVID-19 ML</p>
      </footer>
    </GlassContainer>
  );
}

export default App;
