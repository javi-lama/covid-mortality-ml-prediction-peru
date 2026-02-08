import { Component } from 'react';
import type { ErrorInfo, ReactNode } from 'react';
import { GlassCard } from './ui/GlassCard';

interface Props {
    children: ReactNode;
}

interface State {
    hasError: boolean;
    error: Error | null;
}

export class ErrorBoundary extends Component<Props, State> {
    state: State = { hasError: false, error: null };

    static getDerivedStateFromError(error: Error): State {
        return { hasError: true, error };
    }

    componentDidCatch(error: Error, info: ErrorInfo) {
        console.error('ErrorBoundary caught:', error, info);
    }

    render() {
        if (this.state.hasError) {
            return (
                <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-blue-50 via-indigo-50 to-purple-50 p-4">
                    <GlassCard className="max-w-md text-center p-6">
                        <div className="text-5xl mb-4">&#9888;&#65039;</div>
                        <h2 className="text-xl font-bold text-slate-800 mb-2">
                            Algo salió mal
                        </h2>
                        <p className="text-slate-600 mb-4">
                            Ocurrió un error inesperado. Por favor, recargue la página e intente nuevamente.
                        </p>
                        {import.meta.env.DEV && this.state.error && (
                            <details className="text-left bg-red-50 p-3 rounded-lg mb-4 text-sm">
                                <summary className="cursor-pointer font-medium text-red-700">
                                    Detalles del Error
                                </summary>
                                <pre className="mt-2 whitespace-pre-wrap text-red-600 overflow-auto max-h-40 text-xs">
                                    {this.state.error.toString()}
                                </pre>
                            </details>
                        )}
                        <button
                            onClick={() => window.location.reload()}
                            className="px-6 py-2 bg-indigo-600 hover:bg-indigo-700 text-white font-semibold rounded-xl transition-colors"
                        >
                            Recargar Página
                        </button>
                    </GlassCard>
                </div>
            );
        }

        return this.props.children;
    }
}
