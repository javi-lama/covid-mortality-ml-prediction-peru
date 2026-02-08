import React from 'react';

interface GlassContainerProps {
    children: React.ReactNode;
}

export const GlassContainer: React.FC<GlassContainerProps> = ({ children }) => {
    return (
        <div className="min-h-screen w-full bg-gradient-to-br from-[#E0EAFC] via-[#CFDEF3] to-[#B2CBE8] px-3 py-4 md:px-4 md:py-6 lg:px-6">
            <div className="mx-auto max-w-6xl">
                {children}
            </div>
        </div>
    );
};
