import React from 'react';
import type { HTMLMotionProps } from 'framer-motion';
import { motion } from 'framer-motion';
import { clsx } from 'clsx';
import { twMerge } from 'tailwind-merge';

interface GlassCardProps extends Omit<HTMLMotionProps<"div">, "ref"> {
    children: React.ReactNode;
    className?: string;
    delay?: number;
}

export const GlassCard: React.FC<GlassCardProps> = ({
    children,
    className,
    delay = 0,
    ...props
}) => {
    return (
        <motion.div
            initial={{ opacity: 0, y: 15 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.3, delay, ease: "easeOut" }}
            className={twMerge(
                clsx(
                    // Base Glassmorphism
                    "relative overflow-hidden rounded-xl border border-white/20 shadow-lg",
                    "bg-white/70 backdrop-blur-xl supports-[backdrop-filter]:bg-white/40",
                    // Hover effect
                    "transition-all duration-300 hover:shadow-xl hover:bg-white/50",
                    // Compact padding default
                    "p-4 md:p-5",
                    className
                )
            )}
            {...props}
        >
            {/* Subtle Gradient Overlay */}
            <div className="pointer-events-none absolute inset-0 bg-gradient-to-br from-white/40 to-transparent opacity-50" />

            {/* Content */}
            <div className="relative z-10">
                {children}
            </div>
        </motion.div>
    );
};
