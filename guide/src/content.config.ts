import { defineCollection } from 'astro:content';
import { docsLoader } from '@astrojs/starlight/loaders';
import { docsSchema } from '@astrojs/starlight/schema';
import { z } from 'astro/zod';

const evidenceSchema = ({ image }: { image: () => z.ZodType }) =>
  z.object({
    id: z.string().min(1),
    image: image(),
    alt: z.string().min(1),
    capturedAt: z.coerce.date(),
    device: z.string().min(1),
    os: z.string().min(1),
    appearance: z.enum(['light', 'dark']).optional(),
    scene: z.string().min(1),
    sourceCommit: z.string().regex(/^[0-9a-f]{7,40}$/),
    sourceBranch: z.string().min(1).optional(),
    sha256: z.string().regex(/^[0-9a-f]{64}$/),
    status: z.enum(['real-device', 'preview-placeholder']),
  });

export const collections = {
  docs: defineCollection({
    loader: docsLoader(),
    schema: docsSchema({
      extend: ({ image }) =>
        z.object({
          component: z
            .object({
              id: z.string().regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/),
              kind: z.enum(['surface', 'control', 'indicator', 'navigation', 'dialog', 'card']),
              status: z.enum(['preview', 'stable', 'deprecated']),
              definition: z.string().min(1),
              capabilities: z
                .array(
                  z.object({
                    id: z.string().min(1),
                    title: z.string().min(1),
                    description: z.string().min(1),
                  })
                )
                .min(1),
              states: z.array(z.string().min(1)).min(1),
              platforms: z.array(z.string().min(1)).min(1),
            })
            .optional(),
          evidence: z.array(evidenceSchema({ image })).default([]),
        }),
    }),
  }),
};
