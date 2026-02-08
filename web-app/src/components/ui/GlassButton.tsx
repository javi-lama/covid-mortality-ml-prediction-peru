import React from 'react';
import { clsx } from 'clsx';
import { twMerge } from 'tailwind-merge';
import type { HTMLMotionProps } from 'framer-motion';
import { motion } from 'framer-motion';

interface GlassButtonProps extends Omit<HTMLMotionProps<"button">, "ref"> {
    variant?: 'primary' | 'secondary';
    isLoading?: boolean;
}

export const GlassButton: React.FC<GlassButtonProps> = ({
    children,
    className,
    variant = 'primary',
    isLoading = false,
    disabled,
    ...props
}) => {
    return (
        <motion.button
            whileHover={{ scale: 1.02 }}
            whileTap={{ scale: 0.98 }}
            className={twMerge(
                clsx(
                    "flex items-center justify-center rounded-xl px-6 py-3 font-semibold transition-all duration-300",
                    "disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:scale-100",
                    {
                        // Primary: Gradient Blue/Teal
                        "bg-gradient-to-r from-blue-600 to-teal-500 text-white shadow-lg shadow-blue-500/30 hover:shadow-blue-500/50 hover:to-teal-400": variant === 'primary',
                        // Secondary: Glass White
                        "bg-white/50 text-slate-700 shadow-sm border border-white/40 hover:bg-white/70": variant === 'secondary'
                    },
                    className
                )
            )}
            disabled={isLoading || disabled}
            {...props}
        >
            {isLoading ? (
                <>
                    <svg className="mr-2 h-4 w-4 animate-spin" viewBox="0 0 24 24">
                        <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
                        <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
                    </svg>
                    Processing...
                </>
            ) : children}
        </motion.button>
    );
};
