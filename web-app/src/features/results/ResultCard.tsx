import { GlassCard } from '../../components/ui/GlassCard';
import type { PredictionResponse } from '../../api/client';
import { clsx } from 'clsx';

interface ResultCardProps {
    result: PredictionResponse;
}

// Map English risk levels to Spanish
const riskLevelSpanish: Record<string, string> = {
    'Low': 'Bajo',
    'Moderate': 'Moderado',
    'High': 'Alto',
    'Unknown': 'Desconocido'
};

export const ResultCard = ({ result }: ResultCardProps) => {
    // Safe property extraction with defaults
    const riskLevel = result?.risk_level ?? 'Unknown';
    const riskLevelEs = riskLevelSpanish[riskLevel] ?? riskLevel;
    const riskPercentage = result?.risk_percentage ?? 0;
    const isHighRisk = riskLevel === 'High' || riskLevel === 'Moderate';

    return (
        <GlassCard className="w-full h-full flex flex-col justify-center items-center text-center !p-4">
            <h3 className="text-lg font-medium text-slate-500 uppercase tracking-wider mb-3">
                Evaluación de Riesgo de Mortalidad
            </h3>

            <div className={clsx(
                "text-5xl font-bold mb-2",
                isHighRisk ? "text-red-500" : "text-green-500"
            )}>
                {riskPercentage}%
            </div>

            <div className={clsx(
                "inline-flex items-center justify-center px-4 py-1 rounded-full text-sm font-bold mb-4",
                isHighRisk ? "bg-red-100 text-red-700" : "bg-green-100 text-green-700"
            )}>
                RIESGO {riskLevelEs.toUpperCase()}
            </div>

            {/* Only render threshold info if available */}
            {result?.threshold_info && (
                <div className="bg-white/40 rounded-xl p-3 w-full text-left text-xs text-slate-600 border border-white/30">
                    <p className="font-semibold mb-1">Nota Clínica:</p>
                    <p>{result.threshold_info.note ? 'Umbral optimizado para 90% de sensibilidad' : 'Umbral optimizado para 90% de sensibilidad'}</p>
                    <p className="mt-1 opacity-75">
                        Basado en umbral óptimo: {result.threshold_info.optimal_threshold ?? 0.3184}
                    </p>
                </div>
            )}
        </GlassCard>
    );
};
