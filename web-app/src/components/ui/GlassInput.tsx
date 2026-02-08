import React from 'react';
import { clsx } from 'clsx';
import { twMerge } from 'tailwind-merge';

interface GlassInputProps extends React.InputHTMLAttributes<HTMLInputElement | HTMLSelectElement> {
    label: string;
    error?: string;
    as?: 'input' | 'select';
    children?: React.ReactNode;
}

export const GlassInput = React.forwardRef<HTMLInputElement | HTMLSelectElement, GlassInputProps>(
    ({ label, error, className, as = 'input', children, ...props }, ref) => {
        const Component = as as any;

        return (
            <div className="flex flex-col gap-1.5">
                <label className="ml-1 text-sm font-medium text-slate-600">
                    {label}
                </label>

                <Component
                    ref={ref}
                    className={twMerge(
                        clsx(
                            // Base styles
                            "w-full rounded-xl border border-white/40 bg-white/50 px-4 py-3 text-slate-800",
                            "shadow-sm transition-all duration-200 outline-none backdrop-blur-sm",
                            "placeholder:text-slate-400 focus:border-blue-500 focus:bg-white/80 focus:ring-4 focus:ring-blue-500/10",
                            // Error state
                            error && "border-red-400 bg-red-50/50 text-red-900 focus:border-red-500 focus:ring-red-500/10",
                            className
                        )
                    )}
                    {...props}
                >
                    {children}
                </Component>

                {error && (
                    <span className="ml-1 text-xs font-medium text-red-500 animate-pulse">
                        {error}
                    </span>
                )}
            </div>
        );
    }
);

GlassInput.displayName = 'GlassInput';
