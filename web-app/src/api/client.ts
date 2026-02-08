import axios from 'axios';

// Use environment variable for API URL, with fallback for local development
const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:8000';

export interface PatientData {
    edad: number;
    sexo: "hombre" | "mujer";
    severidad_sars: "Leve" | "Moderado" | "Severo";
    albumina: number;
    plaquetas: number;
    bilirrtotal: number;
    sxingr_disnea: boolean;
    sxingr_cefalea: boolean;
}

export interface PredictionResponse {
    risk_score: number;
    risk_percentage: number;
    risk_level: "Low" | "Moderate" | "High";
    threshold_info: {
        optimal_threshold: number;
        note: string;
        classification: string;
    };
    imputation_diagnostics: {
        method: string;
        observed_vars: number;
        imputed_vars: number;
        imputation_pct: number;
        rationale: string;
    };
    explanation: Array<{
        variable: string;
        variable_clean: string;
        contribution: number;
        sign: number;
    }>;
}

export const predictRisk = async (data: PatientData): Promise<PredictionResponse> => {
    try {
        const response = await axios.post<PredictionResponse>(`${API_URL}/predict`, data);
        return response.data;
    } catch (error) {
        console.error("API Error:", error);
        throw error;
    }
};

// Health check function for startup validation
export const checkHealth = async (): Promise<boolean> => {
    try {
        const response = await axios.get(`${API_URL}/health`);
        return response.status === 200;
    } catch {
        return false;
    }
};
