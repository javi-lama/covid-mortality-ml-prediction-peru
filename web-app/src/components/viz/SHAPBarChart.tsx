import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Cell, ReferenceLine } from 'recharts';
import { GlassCard } from '../ui/GlassCard';

interface SHAPBarChartProps {
    data?: Array<{
        variable_clean: string;
        contribution: number;
        sign: number;
    }> | null;
}

/**
 * Symmetric logarithmic transformation for SHAP values
 * Handles both positive and negative values while compressing large magnitudes
 *
 * Formula: sign(x) × log₁₀(1 + |x| × scaleFactor)
 *
 * This is similar to matplotlib's symlog scale, commonly used in scientific visualization
 * Reference: https://matplotlib.org/stable/api/_as_gen/matplotlib.scale.SymmetricalLogScale.html
 */
const symlogTransform = (value: number, scaleFactor: number = 50): number => {
    const sign = value >= 0 ? 1 : -1;
    return sign * Math.log10(1 + Math.abs(value) * scaleFactor);
};

// Custom tooltip to show original SHAP values (not transformed)
const CustomTooltip = ({ active, payload }: any) => {
    if (active && payload && payload.length) {
        const data = payload[0].payload;
        const originalValue = data.contribution_original;
        const isPositive = originalValue > 0;

        return (
            <div className="bg-white/95 backdrop-blur-sm rounded-lg p-3 shadow-lg border border-slate-200">
                <p className="font-semibold text-slate-700 text-sm">{data.variable_clean}</p>
                <p className={`text-sm font-medium ${isPositive ? 'text-red-600' : 'text-green-600'}`}>
                    Contribución: {originalValue > 0 ? '+' : ''}{originalValue.toFixed(4)}
                </p>
                <p className="text-xs text-slate-500 mt-1">
                    {isPositive ? '↑ Aumenta riesgo de mortalidad' : '↓ Disminuye riesgo de mortalidad'}
                </p>
            </div>
        );
    }
    return null;
};

export const SHAPBarChart = ({ data }: SHAPBarChartProps) => {
    // Guard: ensure data is valid array with items
    const validData = Array.isArray(data) && data.length > 0 ? data : [];

    // Empty state when no data available
    if (validData.length === 0) {
        return (
            <GlassCard className="w-full h-full min-h-[300px] flex items-center justify-center !p-4">
                <div className="text-center text-slate-500">
                    <div className="text-4xl mb-3">📊</div>
                    <p className="font-medium">No hay datos de factores de riesgo</p>
                    <p className="text-sm mt-1 opacity-75">No se pudieron calcular los factores de riesgo</p>
                </div>
            </GlassCard>
        );
    }

    // Transform data using symmetric log scale for visualization
    // Keep original values for tooltip display
    const transformedData = validData.map(item => ({
        ...item,
        contribution_display: symlogTransform(item.contribution),
        contribution_original: item.contribution
    }));

    // Calculate dynamic height based on number of variables (minimum 8 bars)
    const barHeight = 32; // pixels per bar
    const chartHeight = Math.max(transformedData.length * barHeight, 256);

    return (
        <GlassCard className="w-full h-full !p-4">
            <h3 className="text-base font-semibold text-slate-700 mb-3">
                Factores de Riesgo Clave (Valores SHAP)
            </h3>

            <div style={{ height: `${chartHeight}px` }} className="w-full">
                <ResponsiveContainer width="100%" height="100%">
                    <BarChart
                        layout="vertical"
                        data={transformedData}
                        margin={{ top: 5, right: 20, left: 5, bottom: 5 }}
                    >
                        <XAxis type="number" hide />
                        <YAxis
                            type="category"
                            dataKey="variable_clean"
                            width={85}
                            tick={{ fontSize: 11, fill: '#475569' }}
                            tickLine={false}
                            axisLine={false}
                        />
                        <Tooltip
                            content={<CustomTooltip />}
                            cursor={{ fill: 'transparent' }}
                        />
                        <ReferenceLine x={0} stroke="#94a3b8" strokeWidth={1} />
                        <Bar
                            dataKey="contribution_display"
                            radius={[0, 4, 4, 0]}
                            maxBarSize={24}
                        >
                            {transformedData.map((entry, index) => (
                                <Cell
                                    key={`cell-${index}`}
                                    fill={(entry?.contribution_original ?? 0) > 0 ? '#ef4444' : '#22c55e'}
                                />
                            ))}
                        </Bar>
                    </BarChart>
                </ResponsiveContainer>
            </div>

            {/* Legend and scale indicator */}
            <div className="mt-3 flex flex-col items-center gap-2">
                <div className="flex justify-center gap-4 text-xs text-slate-500">
                    <div className="flex items-center gap-1.5">
                        <div className="w-3 h-3 rounded bg-red-500"></div>
                        <span>Aumenta Riesgo</span>
                    </div>
                    <div className="flex items-center gap-1.5">
                        <div className="w-3 h-3 rounded bg-green-500"></div>
                        <span>Disminuye Riesgo</span>
                    </div>
                </div>
                <p className="text-[10px] text-slate-400 italic">
                    Escala logarítmica simétrica
                </p>
            </div>
        </GlassCard>
    );
};
