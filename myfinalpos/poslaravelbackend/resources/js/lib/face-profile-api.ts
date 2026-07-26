import { laravelFetch } from '@/lib/laravel-fetch';

export type FaceProfile = {
    user_id: number;
    full_name: string;
    role: string;
    status: number;
    enrolled_at: string;
    confidence: number;
};

export type FaceVerifyResult = {
    matched: boolean;
    user_id?: number;
    full_name?: string;
    role?: string;
    distance?: number;
    confidence?: number;
    message?: string;
};

export async function fetchFaceProfiles(): Promise<FaceProfile[]> {
    const body = await laravelFetch<{ data: FaceProfile[] }>(
        '/pos/staff/face-profiles',
    );
    return body.data;
}

export async function enrollFaceProfile(input: {
    user_id: number;
    descriptor?: number[];
    descriptors?: number[][];
    confidence?: number;
}): Promise<FaceProfile> {
    const payload =
        input.descriptors && input.descriptors.length > 0
            ? {
                  user_id: input.user_id,
                  descriptors: input.descriptors,
                  confidence: input.confidence,
              }
            : {
                  user_id: input.user_id,
                  descriptor: input.descriptor ?? [],
                  confidence: input.confidence,
              };

    const body = await laravelFetch<{ data: FaceProfile; message: string }>(
        '/pos/staff/face-profiles',
        {
            method: 'POST',
            body: JSON.stringify(payload),
        },
    );
    return body.data;
}

export async function verifyFaceProfile(
    descriptor: number[],
): Promise<FaceVerifyResult> {
    const body = await laravelFetch<{ data: FaceVerifyResult }>(
        '/pos/staff/face-profiles/verify',
        {
            method: 'POST',
            body: JSON.stringify({ descriptor }),
        },
    );
    return body.data;
}

export async function deleteFaceProfile(userId: number): Promise<void> {
    await laravelFetch(`/pos/staff/face-profiles/${userId}`, {
        method: 'DELETE',
    });
}
