import * as faceapi from '@vladmandic/face-api';

const MODEL_URL =
    'https://cdn.jsdelivr.net/npm/@vladmandic/face-api@1.7.14/model';

export const DUPLICATE_THRESHOLD = 0.38;

export const VERIFY_THRESHOLD = 0.46;

export const MIN_VERIFY_CONFIDENCE = 50;

/** Same-person check across the 3 enrollment distances. */
export const ENROLLMENT_CAPTURE_THRESHOLD = 0.52;

export type EnrollmentGuidePhase =
    | 'prepare'
    | 'countdown'
    | 'hold'
    | 'done'
    | 'reposition';

export type EnrollmentGuideUpdate = {
    step: number;
    total: number;
    phase: EnrollmentGuidePhase;
    title: string;
    message: string;
    countdown?: number;
};

export const ENROLLMENT_CAPTURE_STEPS = [
    {
        key: 'far',
        label: 'Far',
        title: 'Step 1 of 3 — Far',
        prepare: 'Move back from the camera. Head and shoulders should be visible.',
        waitFace: 'Center your face in the oval…',
        hold: 'Hold steady — capturing far view',
        done: 'Far capture saved',
        reposition: 'Now move to a normal arm’s length for step 2.',
    },
    {
        key: 'mid',
        label: 'Medium',
        title: 'Step 2 of 3 — Medium',
        prepare: 'Normal distance — face the camera directly.',
        waitFace: 'Keep your face centered in the oval…',
        hold: 'Hold steady — capturing medium view',
        done: 'Medium capture saved',
        reposition: 'Now move closer for the final capture.',
    },
    {
        key: 'close',
        label: 'Close',
        title: 'Step 3 of 3 — Close',
        prepare: 'Move closer until your face nearly fills the oval.',
        waitFace: 'Look straight at the camera…',
        hold: 'Hold steady — capturing close view',
        done: 'Close capture saved',
        reposition: '',
    },
] as const;

function delay(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

const MIN_DETECTION_SCORE = 0.38;

const TINY_DETECTOR_ATTEMPTS = [
    { inputSize: 608, scoreThreshold: 0.16 },
    { inputSize: 512, scoreThreshold: 0.2 },
    { inputSize: 416, scoreThreshold: 0.26 },
    { inputSize: 320, scoreThreshold: 0.32 },
] as const;

let modelsLoaded = false;
let modelsLoading: Promise<void> | null = null;

type DetectionInput = HTMLVideoElement | HTMLCanvasElement;

type FaceMatch = {
    descriptor: Float32Array;
    score: number;
};

export async function ensureFaceModels(): Promise<void> {
    if (modelsLoaded) return;
    if (modelsLoading) {
        await modelsLoading;
        return;
    }

    modelsLoading = (async () => {
        await Promise.all([
            faceapi.nets.tinyFaceDetector.loadFromUri(MODEL_URL),
            faceapi.nets.ssdMobilenetv1.loadFromUri(MODEL_URL),
            faceapi.nets.faceLandmark68Net.loadFromUri(MODEL_URL),
            faceapi.nets.faceRecognitionNet.loadFromUri(MODEL_URL),
        ]);
        modelsLoaded = true;
    })();

    await modelsLoading;
}

async function waitForVideoFrame(
    video: HTMLVideoElement,
    attempts = 30,
): Promise<boolean> {
    for (let i = 0; i < attempts; i += 1) {
        if (video.readyState >= 2 && video.videoWidth > 0 && video.videoHeight > 0) {
            return true;
        }
        await new Promise((resolve) => setTimeout(resolve, 100));
    }

    return video.readyState >= 2 && video.videoWidth > 0;
}

function createVideoFrameCanvas(video: HTMLVideoElement): HTMLCanvasElement | null {
    if (video.videoWidth === 0 || video.videoHeight === 0) {
        return null;
    }

    const canvas = document.createElement('canvas');
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    const context = canvas.getContext('2d', { willReadFrequently: true });
    if (!context) {
        return null;
    }

    context.drawImage(video, 0, 0, canvas.width, canvas.height);
    return canvas;
}

function detectionInputs(video: HTMLVideoElement): DetectionInput[] {
    const canvas = createVideoFrameCanvas(video);
    return canvas ? [canvas, video] : [video];
}

function faceArea(
    detection: faceapi.WithFaceDescriptor<
        faceapi.WithFaceLandmarks<
            { detection: faceapi.FaceDetection },
            faceapi.FaceLandmarks68
        >
    >,
): number {
    const box = detection.detection.box;
    return box.width * box.height;
}

function pickBestMatch(matches: FaceMatch[]): FaceMatch | null {
    const viable = matches.filter(
        (match) => match.score >= MIN_DETECTION_SCORE,
    );
    if (viable.length === 0) {
        return null;
    }

    return viable.reduce((best, current) =>
        current.score > best.score ? current : best,
    );
}

export function l2Normalize(descriptor: number[]): number[] {
    let sum = 0;
    for (const value of descriptor) {
        sum += value * value;
    }

    const norm = Math.sqrt(sum);
    if (norm < 1e-10) {
        return descriptor;
    }

    return descriptor.map((value) => value / norm);
}

async function detectWithTiny(
    input: DetectionInput,
    options: faceapi.TinyFaceDetectorOptions,
): Promise<FaceMatch | null> {
    const single = await faceapi
        .detectSingleFace(input, options)
        .withFaceLandmarks()
        .withFaceDescriptor();

    if (single?.descriptor) {
        return {
            descriptor: single.descriptor,
            score: single.detection.score,
        };
    }

    const all = await faceapi
        .detectAllFaces(input, options)
        .withFaceLandmarks()
        .withFaceDescriptors();

    if (all.length === 0) {
        return null;
    }

    const best = all.reduce((current, candidate) =>
        faceArea(candidate) > faceArea(current) ? candidate : current,
    );

    if (!best.descriptor) {
        return null;
    }

    return {
        descriptor: best.descriptor,
        score: best.detection.score,
    };
}

async function detectWithSsd(input: DetectionInput): Promise<FaceMatch | null> {
    const options = new faceapi.SsdMobilenetv1Options({
        minConfidence: 0.4,
        maxResults: 5,
    });

    const all = await faceapi
        .detectAllFaces(input, options)
        .withFaceLandmarks()
        .withFaceDescriptors();

    if (all.length === 0) {
        return null;
    }

    const best = all.reduce((current, candidate) =>
        faceArea(candidate) > faceArea(current) ? candidate : current,
    );

    if (!best.descriptor) {
        return null;
    }

    return {
        descriptor: best.descriptor,
        score: best.detection.score,
    };
}

async function detectBestDescriptor(
    video: HTMLVideoElement,
): Promise<Float32Array | null> {
    const matches: FaceMatch[] = [];
    const inputs = detectionInputs(video);

    for (const input of inputs) {
        const ssdMatch = await detectWithSsd(input);
        if (ssdMatch) {
            matches.push(ssdMatch);
        }

        for (const config of TINY_DETECTOR_ATTEMPTS) {
            const options = new faceapi.TinyFaceDetectorOptions({
                inputSize: config.inputSize,
                scoreThreshold: config.scoreThreshold,
            });
            const match = await detectWithTiny(input, options);
            if (match) {
                matches.push(match);
            }
        }
    }

    const best = pickBestMatch(matches);
    return best?.descriptor ?? null;
}

export async function probeFaceInVideo(
    video: HTMLVideoElement,
): Promise<boolean> {
    await ensureFaceModels();

    if (video.readyState < 2 || video.videoWidth === 0) {
        return false;
    }

    const inputs = detectionInputs(video);
    const options = new faceapi.TinyFaceDetectorOptions({
        inputSize: 512,
        scoreThreshold: 0.28,
    });

    for (const input of inputs) {
        const detection = await faceapi.detectSingleFace(input, options);
        if (detection) {
            return true;
        }

        const ssd = await faceapi.detectSingleFace(
            input,
            new faceapi.SsdMobilenetv1Options({ minConfidence: 0.28 }),
        );
        if (ssd) {
            return true;
        }
    }

    return false;
}

export async function captureFaceDescriptor(
    video: HTMLVideoElement,
    onProgress?: (attempt: number, total: number) => void,
): Promise<number[] | null> {
    await ensureFaceModels();

    const ready = await waitForVideoFrame(video);
    if (!ready) {
        return null;
    }

    if (video.paused) {
        await video.play().catch(() => undefined);
    }

    const frameAttempts = 15;
    for (let frame = 0; frame < frameAttempts; frame += 1) {
        onProgress?.(frame + 1, frameAttempts);

        if (frame > 0) {
            await new Promise((resolve) => setTimeout(resolve, 220));
        } else {
            await new Promise((resolve) => setTimeout(resolve, 350));
        }

        const descriptor = await detectBestDescriptor(video);
        if (descriptor) {
            return l2Normalize(Array.from(descriptor));
        }
    }

    return null;
}

export function distanceToConfidence(
    distance: number,
    threshold = VERIFY_THRESHOLD,
): number {
    return Math.max(
        0,
        Math.min(100, Math.round((1 - distance / threshold) * 100)),
    );
}

export function descriptorDistance(a: number[], b: number[]): number {
    let sum = 0;
    for (let i = 0; i < a.length; i += 1) {
        const delta = a[i] - b[i];
        sum += delta * delta;
    }

    return Math.sqrt(sum);
}

export function averageDescriptors(descriptors: number[][]): number[] {
    if (descriptors.length === 0) {
        return [];
    }

    const length = descriptors[0].length;
    const totals = new Array<number>(length).fill(0);

    for (const descriptor of descriptors) {
        for (let i = 0; i < length; i += 1) {
            totals[i] += descriptor[i];
        }
    }

    return totals.map((value) => value / descriptors.length);
}

/** Weight medium capture highest — best for daily verify distance. */
/** How consistent the 3 enrollment captures are (not the same as live verify %). */
export function computeEnrollmentQuality(captures: number[][]): number {
    if (captures.length < 2) {
        return 0;
    }

    let distanceSum = 0;
    let pairs = 0;

    for (let i = 0; i < captures.length; i += 1) {
        for (let j = i + 1; j < captures.length; j += 1) {
            distanceSum += descriptorDistance(captures[i], captures[j]);
            pairs += 1;
        }
    }

    const averageDistance = distanceSum / pairs;

    return Math.max(
        0,
        Math.min(
            100,
            Math.round(
                (1 - averageDistance / ENROLLMENT_CAPTURE_THRESHOLD) * 100,
            ),
        ),
    );
}

export function buildEnrollmentTemplate(captures: number[][]): number[] {
    if (captures.length === 1) {
        return captures[0];
    }

    if (captures.length === 3) {
        const weights = [0.25, 0.5, 0.25];
        const length = captures[0].length;
        const totals = new Array<number>(length).fill(0);

        for (let index = 0; index < captures.length; index += 1) {
            for (let i = 0; i < length; i += 1) {
                totals[i] += captures[index][i] * weights[index];
            }
        }

        return totals;
    }

    return averageDescriptors(captures);
}

async function waitForStableFace(
    video: HTMLVideoElement,
    onUpdate: (update: EnrollmentGuideUpdate) => void,
    step: number,
    total: number,
    stepInfo: (typeof ENROLLMENT_CAPTURE_STEPS)[number],
): Promise<boolean> {
    let stableTicks = 0;

    for (let attempt = 0; attempt < 36; attempt += 1) {
        const detected = await probeFaceInVideo(video);
        if (detected) {
            stableTicks += 1;
            onUpdate({
                step,
                total,
                phase: 'prepare',
                title: stepInfo.title,
                message:
                    stableTicks >= 2
                        ? 'Face detected — get ready…'
                        : stepInfo.waitFace,
            });
            if (stableTicks >= 2) {
                return true;
            }
        } else {
            stableTicks = 0;
            onUpdate({
                step,
                total,
                phase: 'prepare',
                title: stepInfo.title,
                message: stepInfo.waitFace,
            });
        }

        await delay(450);
    }

    return false;
}

async function countdownAndCapture(
    video: HTMLVideoElement,
    onUpdate: (update: EnrollmentGuideUpdate) => void,
    step: number,
    total: number,
    stepInfo: (typeof ENROLLMENT_CAPTURE_STEPS)[number],
): Promise<number[] | null> {
    for (let count = 3; count >= 1; count -= 1) {
        onUpdate({
            step,
            total,
            phase: 'countdown',
            title: stepInfo.title,
            message: count === 1 ? 'Hold steady…' : 'Get ready…',
            countdown: count,
        });
        await delay(850);
    }

    onUpdate({
        step,
        total,
        phase: 'hold',
        title: stepInfo.title,
        message: stepInfo.hold,
    });

    const descriptor = await captureFaceDescriptor(video, (attempt, frameTotal) => {
        onUpdate({
            step,
            total,
            phase: 'hold',
            title: stepInfo.title,
            message: `Hold steady — reading ${attempt}/${frameTotal}`,
        });
    });

    return descriptor;
}

export function descriptorsAreSamePerson(
    descriptors: number[][],
    threshold = ENROLLMENT_CAPTURE_THRESHOLD,
): boolean {
    for (let i = 0; i < descriptors.length; i += 1) {
        for (let j = i + 1; j < descriptors.length; j += 1) {
            if (descriptorDistance(descriptors[i], descriptors[j]) > threshold) {
                return false;
            }
        }
    }

    return descriptors.length > 0;
}

export async function captureEnrollmentDescriptors(
    video: HTMLVideoElement,
    onUpdate?: (update: EnrollmentGuideUpdate) => void,
): Promise<number[][] | null> {
    const captures: number[][] = [];
    const total = ENROLLMENT_CAPTURE_STEPS.length;

    for (let step = 0; step < ENROLLMENT_CAPTURE_STEPS.length; step += 1) {
        const stepInfo = ENROLLMENT_CAPTURE_STEPS[step];
        const stepNumber = step + 1;

        if (step > 0 && stepInfo.reposition) {
            onUpdate?.({
                step: stepNumber,
                total,
                phase: 'reposition',
                title: stepInfo.title,
                message: ENROLLMENT_CAPTURE_STEPS[step - 1].reposition,
            });
            await delay(2400);
        }

        onUpdate?.({
            step: stepNumber,
            total,
            phase: 'prepare',
            title: stepInfo.title,
            message: stepInfo.prepare,
        });
        await delay(900);

        const ready = await waitForStableFace(
            video,
            (update) => onUpdate?.(update),
            stepNumber,
            total,
            stepInfo,
        );

        if (!ready) {
            return null;
        }

        const descriptor = await countdownAndCapture(
            video,
            (update) => onUpdate?.(update),
            stepNumber,
            total,
            stepInfo,
        );

        if (!descriptor) {
            return null;
        }

        captures.push(descriptor);

        onUpdate?.({
            step: stepNumber,
            total,
            phase: 'done',
            title: stepInfo.title,
            message: stepInfo.done,
        });

        if (step < ENROLLMENT_CAPTURE_STEPS.length - 1) {
            await delay(1200);
        }
    }

    return captures;
}

export async function captureVerifyDescriptors(
    video: HTMLVideoElement,
    onUpdate?: (message: string) => void,
): Promise<number[][]> {
    const captures: number[][] = [];

    for (let attempt = 0; attempt < 3; attempt += 1) {
        if (attempt > 0) {
            onUpdate?.('Hold steady for another read…');
            await delay(700);
        } else {
            onUpdate?.('Look at the camera — hold steady…');
            await delay(500);
        }

        const descriptor = await captureFaceDescriptor(video, (frame, total) => {
            onUpdate?.(`Verifying ${attempt + 1}/3 — frame ${frame}/${total}`);
        });

        if (descriptor) {
            captures.push(descriptor);
        }
    }

    return captures;
}
