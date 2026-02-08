import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { GlassCard } from '../../components/ui/GlassCard';
import { GlassInput } from '../../components/ui/GlassInput';
import { GlassButton } from '../../components/ui/GlassButton';
import type { PatientData } from '../../api/client';

const patientSchema = z.object({
    edad: z.coerce.number().min(18, "La edad debe ser 18+").max(120, "Edad inválida"),
    sexo: z.enum(["hombre", "mujer"]),
    severidad_sars: z.enum(["Leve", "Moderado", "Severo"]),
    albumina: z.coerce.number().min(1, "Mín 1.0").max(6, "Máx 6.0"),
    plaquetas: z.coerce.number().min(1000, "Valor inválido").max(1000000, "Valor muy alto"),
    bilirrtotal: z.coerce.number().min(0.1, "Mín 0.1").max(20, "Máx 20.0"),
    sxingr_disnea: z.string().transform(val => val === 'true'),
    sxingr_cefalea: z.string().transform(val => val === 'true'),
});

interface RiskFormProps {
    onSubmit: (data: PatientData) => void;
    isLoading: boolean;
}

export const RiskForm = ({ onSubmit, isLoading }: RiskFormProps) => {
    const { register, handleSubmit, formState: { errors } } = useForm<any>({
        resolver: zodResolver(patientSchema),
        defaultValues: {
            sexo: 'hombre',
            severidad_sars: 'Moderado',
            sxingr_disnea: 'false',
            sxingr_cefalea: 'false'
        }
    });

    return (
        <GlassCard className="w-full max-w-2xl mx-auto !p-4 md:!p-5">
            <div className="mb-4 text-center">
                <h2 className="text-2xl font-bold bg-gradient-to-r from-blue-700 to-teal-600 bg-clip-text text-transparent">
                    Evaluación Clínica
                </h2>
                <p className="text-slate-500 mt-1 text-sm">Ingrese los signos vitales y síntomas del paciente</p>
            </div>

            <form onSubmit={handleSubmit((data) => onSubmit(data as unknown as PatientData))} className="space-y-3">
                {/* Sección 1: Demografía */}
                <div className="grid gap-3 md:grid-cols-2">
                    <GlassInput label="Edad (Años)" type="number" error={errors.edad?.message as string} {...register('edad')} />

                    <GlassInput label="Sexo" as="select" error={errors.sexo?.message as string} {...register('sexo')}>
                        <option value="hombre">Masculino</option>
                        <option value="mujer">Femenino</option>
                    </GlassInput>
                </div>

                {/* Sección 2: Métricas Clínicas */}
                <div className="grid gap-3 md:grid-cols-3">
                    <GlassInput label="Albúmina Sérica (g/dL)" type="number" step="0.1" error={errors.albumina?.message as string} {...register('albumina')} />
                    <GlassInput label="Plaquetas (/μL)" type="number" step="1000" error={errors.plaquetas?.message as string} {...register('plaquetas')} />
                    <GlassInput label="Bilirrubina Total (mg/dL)" type="number" step="0.1" error={errors.bilirrtotal?.message as string} {...register('bilirrtotal')} />
                </div>

                {/* Sección 3: Síntomas y Severidad */}
                <div className="grid gap-3 md:grid-cols-3">
                    <GlassInput label="Severidad SARS" as="select" error={errors.severidad_sars?.message as string} {...register('severidad_sars')}>
                        <option value="Leve">Leve</option>
                        <option value="Moderado">Moderado</option>
                        <option value="Severo">Severo</option>
                    </GlassInput>

                    <GlassInput label="Disnea" as="select" error={errors.sxingr_disnea?.message as string} {...register('sxingr_disnea')}>
                        <option value="false">No</option>
                        <option value="true">Sí</option>
                    </GlassInput>

                    <GlassInput label="Cefalea" as="select" error={errors.sxingr_cefalea?.message as string} {...register('sxingr_cefalea')}>
                        <option value="false">No</option>
                        <option value="true">Sí</option>
                    </GlassInput>
                </div>

                <div className="pt-2 flex justify-end">
                    <GlassButton type="submit" isLoading={isLoading} className="w-full md:w-auto min-w-[180px]">
                        Calcular Riesgo
                    </GlassButton>
                </div>
            </form>
        </GlassCard>
    );
};
