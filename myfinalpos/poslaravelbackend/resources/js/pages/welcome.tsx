import { Head, Link, usePage } from '@inertiajs/react';
import {
    ArrowRight,
    CheckCircle2,
    Clock,
    Egg,
    Facebook,
    Heart,
    Leaf,
    MapPin,
    Quote,
    ShoppingBasket,
    Sparkles,
    Sprout,
    Star,
    Store,
    Tractor,
    Users,
    Wheat,
} from 'lucide-react';
import { BrandLogo } from '@/components/brand-logo';
import { LiveMonitorClock } from '@/components/pos/live-monitor-clock';
import { Button } from '@/components/ui/button';
import { BRAND } from '@/lib/brand';
import { dashboard, login } from '@/routes';

const navLinks = [
    { label: 'About', href: '#about' },
    { label: 'What We Sell', href: '#products' },
    { label: 'Why Us', href: '#why-us' },
    { label: 'Visit Us', href: '#contact' },
];

const highlights = [
    'Animal feed & poultry supplies',
    'Fertilizers & crop inputs',
    'Fair everyday prices',
    'Serving Bayambang growers',
];

const stats = [
    { value: 'Bayambang', label: 'Pangasinan home base' },
    { value: '200+', label: 'Products in stock' },
    { value: '50+', label: 'Local farm customers' },
    { value: '6', label: 'Days open each week' },
];

const products = [
    {
        icon: Egg,
        title: 'Poultry & Animal Feed',
        description:
            'Feeds and supplies for broilers, layers, and backyard flocks — stocked for growers in Bayambang and nearby towns.',
        points: ['Starter & layer feeds', 'Poultry essentials', 'Trusted brands'],
    },
    {
        icon: Sprout,
        title: 'Fertilizers & Crop Inputs',
        description:
            'Fertilizers, soil amendments, and crop care products for rice, corn, vegetables, and other field crops.',
        points: ['NPK & organic options', 'Seasonal stock', 'Grower advice'],
    },
    {
        icon: Tractor,
        title: 'Farm & Garden Essentials',
        description:
            'Seeds, tools, sacks, and everyday farm supplies — one stop for agricultural and poultry needs.',
        points: ['Seeds & supplies', 'Harvest essentials', 'Friendly service'],
    },
];

const values = [
    {
        icon: Leaf,
        title: 'Quality agri products',
        description:
            'We stock feeds, fertilizers, and farm supplies growers rely on — fresh inventory and trusted brands.',
    },
    {
        icon: Users,
        title: 'Neighbors you know',
        description:
            'A local Bayambang supplier that knows its customers. Shopping here feels like talking to a fellow grower.',
    },
    {
        icon: Heart,
        title: 'Honest prices',
        description:
            'Fair everyday prices for farmers, poultry raisers, and backyard growers in Pangasinan.',
    },
];

const testimonials = [
    {
        quote: 'My go-to shop for layer feed and fertilizers. Always helpful and the stock is ready when I need it.',
        name: 'Maria Santos',
        role: 'Poultry raiser, Bayambang',
    },
    {
        quote: 'Good prices on animal feed and crop inputs. Much easier than driving far for every refill.',
        name: 'James Liwanag',
        role: 'Rice & corn farmer',
    },
    {
        quote: 'Reliable supplies for our farm. The staff knows what we need for each season.',
        name: 'Aileen Cruz',
        role: 'Local grower',
    },
];

export default function Welcome() {
    const { auth } = usePage().props;

    return (
        <>
            <Head title={BRAND.pageTitle} />

            <div className="min-h-svh bg-background text-foreground">
                <div className="bg-sidebar text-sidebar-foreground">
                    <div className="mx-auto flex max-w-6xl items-center justify-center gap-2 px-5 py-2 text-center text-xs font-medium md:px-8">
                        <Sparkles className="size-3.5 shrink-0 text-agri-wheat" />
                        <span className="truncate">
                            {BRAND.tagline} in {BRAND.location} — visit us on Provincial Rd.
                        </span>
                    </div>
                </div>

                <header className="sticky top-0 z-50 border-b border-border/50 bg-background/85 backdrop-blur-md">
                    <div className="mx-auto flex h-16 max-w-6xl items-center justify-between gap-4 px-5 md:px-8">
                        <a href="#" className="min-w-0">
                            <BrandLogo size="md" />
                        </a>

                        <nav className="hidden items-center gap-7 lg:flex">
                            {navLinks.map((link) => (
                                <a
                                    key={link.href}
                                    href={link.href}
                                    className="text-sm font-medium text-muted-foreground transition-colors hover:text-foreground"
                                >
                                    {link.label}
                                </a>
                            ))}
                        </nav>

                        <div className="flex shrink-0 items-center gap-2">
                            <Button
                                asChild
                                variant="ghost"
                                size="sm"
                                className="hidden rounded-xl sm:inline-flex"
                            >
                                <a href="#contact">Find the shop</a>
                            </Button>
                            {auth.user ? (
                                <Button asChild size="sm" className="rounded-xl">
                                    <Link href={dashboard()}>
                                        Dashboard
                                        <ArrowRight className="size-4" />
                                    </Link>
                                </Button>
                            ) : (
                                <Button
                                    asChild
                                    variant="outline"
                                    size="sm"
                                    className="rounded-xl"
                                >
                                    <Link href={login()}>Staff login</Link>
                                </Button>
                            )}
                        </div>
                    </div>
                </header>

                <section className="agri-hero-gradient relative overflow-hidden px-5 pt-16 pb-20 md:px-8 md:pt-24 md:pb-24">
                    <div className="pointer-events-none absolute -top-32 right-0 size-[28rem] rounded-full bg-primary/5 blur-3xl" />
                    <div className="pointer-events-none absolute bottom-0 left-0 size-80 rounded-full bg-agri-wheat/10 blur-3xl" />

                    <div className="relative mx-auto grid max-w-6xl items-center gap-14 lg:grid-cols-[1.05fr_0.95fr] lg:gap-16">
                        <div className="flex flex-col gap-6">
                            <span className="agri-eyebrow">
                                <Wheat className="size-3.5" />
                                {BRAND.tagline}
                            </span>

                            <h1 className="text-4xl leading-[1.08] font-bold tracking-tight md:text-5xl lg:text-[3.5rem]">
                                Your local agri & poultry supply,
                                <span className="mt-1 block text-primary">
                                    right here in Bayambang.
                                </span>
                            </h1>

                            <p className="max-w-xl text-base leading-relaxed text-muted-foreground md:text-lg">
                                {BRAND.fullName} serves farmers, poultry raisers,
                                and growers with animal feed, fertilizers, crop
                                inputs, and farm essentials — trusted local service
                                at fair prices.
                            </p>

                            <div className="flex flex-wrap items-center gap-3">
                                <Button
                                    asChild
                                    size="lg"
                                    className="h-12 rounded-xl px-6 text-base"
                                >
                                    <a href="#products">
                                        See what we sell
                                        <ArrowRight className="size-4" />
                                    </a>
                                </Button>
                                <Button
                                    asChild
                                    variant="outline"
                                    size="lg"
                                    className="h-12 rounded-xl px-6 text-base"
                                >
                                    <a
                                        href={BRAND.facebookUrl}
                                        target="_blank"
                                        rel="noreferrer"
                                    >
                                        <Facebook className="size-4" />
                                        Follow on Facebook
                                    </a>
                                </Button>
                            </div>

                            <div className="mt-2 flex flex-wrap items-center gap-x-6 gap-y-2 text-sm text-muted-foreground">
                                {highlights.slice(0, 3).map((item) => (
                                    <span
                                        key={item}
                                        className="inline-flex items-center gap-1.5"
                                    >
                                        <CheckCircle2 className="size-4 text-primary" />
                                        {item}
                                    </span>
                                ))}
                            </div>
                        </div>

                        <div className="relative">
                            <div className="agri-card relative overflow-hidden p-7 md:p-8">
                                <div className="absolute -top-10 -right-10 size-44 rounded-full bg-primary/10 blur-2xl" />
                                <div className="relative flex flex-col gap-6">
                                    <div className="flex flex-col gap-3">
                                        <div className="flex items-start gap-3">
                                            <div className="agri-icon-box size-11 rounded-xl">
                                                <Store className="size-5" />
                                            </div>
                                            <div className="flex flex-col gap-1">
                                                <p className="text-sm font-semibold">
                                                    Open today
                                                </p>
                                                <p className="text-xs text-muted-foreground">
                                                    Mon–Sat · 7AM – 6PM
                                                </p>
                                            </div>
                                        </div>
                                        <div className="flex flex-wrap items-center gap-2">
                                            <LiveMonitorClock variant="chip" />
                                            <span className="live-monitor-chip inline-flex items-center gap-1.5 rounded-full bg-primary/10 font-semibold text-primary">
                                                <span className="size-1.5 animate-pulse rounded-full bg-primary" />
                                                Open
                                            </span>
                                        </div>
                                    </div>

                                    <div className="grid grid-cols-2 gap-3">
                                        {stats.slice(0, 4).map((stat) => (
                                            <div
                                                key={stat.label}
                                                className="rounded-xl border border-border/60 bg-secondary/40 p-4"
                                            >
                                                <p className="text-2xl font-bold text-primary">
                                                    {stat.value}
                                                </p>
                                                <p className="mt-1 text-xs leading-snug text-muted-foreground">
                                                    {stat.label}
                                                </p>
                                            </div>
                                        ))}
                                    </div>

                                    <div className="flex items-center gap-3 rounded-xl border border-dashed border-primary/25 bg-primary/5 px-4 py-3">
                                        <MapPin className="size-5 shrink-0 text-primary" />
                                        <p className="text-sm text-muted-foreground">
                                            <span className="font-semibold text-foreground">
                                                {BRAND.address}
                                            </span>
                                        </p>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </section>

                <section className="border-y border-border/50 bg-card/40 py-8">
                    <div className="mx-auto grid max-w-6xl gap-4 px-5 sm:grid-cols-2 md:px-8 lg:grid-cols-4">
                        {highlights.map((item) => (
                            <div
                                key={item}
                                className="flex items-center gap-2.5 text-sm font-semibold"
                            >
                                <CheckCircle2 className="size-5 shrink-0 text-primary" />
                                {item}
                            </div>
                        ))}
                    </div>
                </section>

                <section
                    id="about"
                    className="agri-landing-section px-5 py-20 md:px-8 md:py-24"
                >
                    <div className="mx-auto grid max-w-6xl items-center gap-12 lg:grid-cols-2 lg:gap-16">
                        <div className="flex flex-col gap-5">
                            <span className="agri-eyebrow">
                                <Sprout className="size-3.5" />
                                Who we are
                            </span>
                            <h2 className="agri-section-title">
                                Serving Bayambang growers & poultry raisers
                            </h2>
                            <p className="leading-relaxed text-muted-foreground">
                                {BRAND.shortName} is a local agricultural and
                                poultry supply shop built for farmers and raisers
                                in Bayambang and nearby Pangasinan communities.
                                We keep the feeds, fertilizers, and farm essentials
                                you need within easy reach.
                            </p>
                            <p className="leading-relaxed text-muted-foreground">
                                Whether you are stocking up on layer feed,
                                preparing fields for the season, or picking up
                                harvest supplies, our team is here to help with
                                friendly, practical service.
                            </p>
                            <div className="mt-2 grid gap-3 sm:grid-cols-2">
                                {[
                                    'Local & trusted supplier',
                                    'Feeds, fertilizers & more',
                                    'Helpful grower advice',
                                    'Open six days a week',
                                ].map((item) => (
                                    <div
                                        key={item}
                                        className="flex items-center gap-2.5 text-sm font-medium"
                                    >
                                        <CheckCircle2 className="size-4 shrink-0 text-primary" />
                                        {item}
                                    </div>
                                ))}
                            </div>
                        </div>

                        <div className="grid gap-4 sm:grid-cols-2">
                            {stats.map((stat) => (
                                <div
                                    key={stat.label}
                                    className="agri-stat-card justify-center text-center"
                                >
                                    <p className="agri-stat-value text-3xl text-primary">
                                        {stat.value}
                                    </p>
                                    <p className="mt-2 text-sm text-muted-foreground">
                                        {stat.label}
                                    </p>
                                </div>
                            ))}
                        </div>
                    </div>
                </section>

                <section
                    id="products"
                    className="agri-landing-section border-t border-border/50 bg-card/40 px-5 py-20 md:px-8 md:py-24"
                >
                    <div className="mx-auto max-w-6xl">
                        <div className="mb-12 max-w-2xl">
                            <span className="agri-eyebrow">
                                <ShoppingBasket className="size-3.5" />
                                What we sell
                            </span>
                            <h2 className="mt-3 agri-section-title">
                                Feeds, fertilizers & farm supplies in one stop
                            </h2>
                            <p className="mt-3 text-muted-foreground">
                                From poultry feed to crop inputs and everyday farm
                                essentials — everything a grower or raiser in
                                Bayambang might need.
                            </p>
                        </div>

                        <div className="grid gap-5 md:grid-cols-3">
                            {products.map((product) => (
                                <div
                                    key={product.title}
                                    className="agri-feature-card"
                                >
                                    <div className="agri-icon-box size-12 rounded-xl">
                                        <product.icon className="size-6" />
                                    </div>
                                    <h3 className="agri-card-title text-lg">
                                        {product.title}
                                    </h3>
                                    <p className="text-sm leading-relaxed text-muted-foreground">
                                        {product.description}
                                    </p>
                                    <ul className="mt-1 flex flex-col gap-2">
                                        {product.points.map((point) => (
                                            <li
                                                key={point}
                                                className="flex items-center gap-2 text-sm font-medium"
                                            >
                                                <CheckCircle2 className="size-4 shrink-0 text-primary" />
                                                {point}
                                            </li>
                                        ))}
                                    </ul>
                                </div>
                            ))}
                        </div>
                    </div>
                </section>

                <section
                    id="why-us"
                    className="agri-landing-section px-5 py-20 md:px-8 md:py-24"
                >
                    <div className="mx-auto max-w-6xl">
                        <div className="mb-12 text-center">
                            <span className="agri-eyebrow mx-auto">
                                <Heart className="size-3.5" />
                                Why {BRAND.shortName}
                            </span>
                            <h2 className="mt-3 agri-section-title">
                                A supplier Bayambang growers can count on
                            </h2>
                        </div>

                        <div className="grid gap-5 md:grid-cols-3">
                            {values.map((value) => (
                                <div
                                    key={value.title}
                                    className="agri-card flex flex-col gap-3 p-6 text-center"
                                >
                                    <div className="agri-icon-box mx-auto size-11 rounded-xl">
                                        <value.icon className="size-5" />
                                    </div>
                                    <h3 className="agri-card-title">
                                        {value.title}
                                    </h3>
                                    <p className="text-sm leading-relaxed text-muted-foreground">
                                        {value.description}
                                    </p>
                                </div>
                            ))}
                        </div>
                    </div>
                </section>

                <section className="border-t border-border/50 bg-card/40 px-5 py-20 md:px-8 md:py-24">
                    <div className="mx-auto max-w-6xl">
                        <div className="mb-12 text-center">
                            <span className="agri-eyebrow mx-auto">
                                <Star className="size-3.5" />
                                Loved by local growers
                            </span>
                            <h2 className="mt-3 agri-section-title">
                                What our customers say
                            </h2>
                        </div>

                        <div className="grid gap-5 md:grid-cols-3">
                            {testimonials.map((t) => (
                                <figure
                                    key={t.name}
                                    className="agri-card flex flex-col gap-4 p-6"
                                >
                                    <Quote className="size-7 text-primary/30" />
                                    <blockquote className="flex-1 text-sm leading-relaxed text-foreground">
                                        “{t.quote}”
                                    </blockquote>
                                    <div className="flex items-center gap-1 text-agri-wheat">
                                        {Array.from({ length: 5 }).map((_, i) => (
                                            <Star
                                                key={i}
                                                className="size-4 fill-current"
                                            />
                                        ))}
                                    </div>
                                    <figcaption className="border-t border-border/50 pt-4">
                                        <p className="text-sm font-semibold">
                                            {t.name}
                                        </p>
                                        <p className="text-xs text-muted-foreground">
                                            {t.role}
                                        </p>
                                    </figcaption>
                                </figure>
                            ))}
                        </div>
                    </div>
                </section>

                <footer
                    id="contact"
                    className="agri-landing-section border-t border-sidebar-border/40 bg-sidebar px-5 py-16 text-sidebar-foreground md:px-8 md:py-20"
                >
                    <div className="mx-auto grid max-w-6xl gap-12 lg:grid-cols-[1.2fr_1.8fr]">
                        <div className="flex flex-col gap-4">
                            <BrandLogo
                                size="md"
                                tone="on-dark"
                                nameClassName="text-sidebar-foreground"
                                subtitleClassName="text-sidebar-foreground/70"
                            />
                            <p className="max-w-md text-sm leading-relaxed text-sidebar-foreground/70">
                                {BRAND.fullName} — your local source for animal
                                feed, fertilizers, poultry supplies, and farm
                                essentials in {BRAND.location}.
                            </p>
                            <a
                                href={BRAND.facebookUrl}
                                target="_blank"
                                rel="noreferrer"
                                className="inline-flex w-fit items-center gap-2 text-sm font-medium text-sidebar-foreground/80 transition-colors hover:text-sidebar-foreground"
                            >
                                <Facebook className="size-4" />
                                facebook.com/{BRAND.facebookHandle}
                            </a>
                            <div className="mt-2 flex flex-wrap gap-3">
                                {navLinks.map((link) => (
                                    <a
                                        key={link.href}
                                        href={link.href}
                                        className="text-xs text-sidebar-foreground/60 transition-colors hover:text-sidebar-foreground"
                                    >
                                        {link.label}
                                    </a>
                                ))}
                            </div>
                        </div>

                        <div className="grid gap-4 sm:grid-cols-2">
                            <div className="flex gap-3 rounded-xl border border-sidebar-border/50 bg-sidebar-accent/40 p-4">
                                <MapPin className="mt-0.5 size-5 shrink-0 text-agri-wheat" />
                                <div>
                                    <p className="text-sm font-semibold">
                                        Visit us
                                    </p>
                                    <p className="mt-1 text-sm text-sidebar-foreground/70">
                                        {BRAND.address}
                                        <br />
                                        {BRAND.location}
                                    </p>
                                </div>
                            </div>
                            <div className="flex gap-3 rounded-xl border border-sidebar-border/50 bg-sidebar-accent/40 p-4">
                                <Facebook className="mt-0.5 size-5 shrink-0 text-agri-wheat" />
                                <div>
                                    <p className="text-sm font-semibold">
                                        Facebook
                                    </p>
                                    <p className="mt-1 text-sm text-sidebar-foreground/70">
                                        <a
                                            href={BRAND.facebookUrl}
                                            target="_blank"
                                            rel="noreferrer"
                                            className="hover:underline"
                                        >
                                            {BRAND.facebookHandle}
                                        </a>
                                        <br />
                                        Message us for inquiries
                                    </p>
                                </div>
                            </div>
                            <div className="flex gap-3 rounded-xl border border-sidebar-border/50 bg-sidebar-accent/40 p-4 sm:col-span-2">
                                <Clock className="mt-0.5 size-5 shrink-0 text-agri-wheat" />
                                <div>
                                    <p className="text-sm font-semibold">
                                        Shop hours
                                    </p>
                                    <p className="mt-1 text-sm text-sidebar-foreground/70">
                                        Monday – Saturday: 7:00 AM – 6:00 PM
                                        &nbsp;·&nbsp; Sunday: 8:00 AM – 1:00 PM
                                    </p>
                                </div>
                            </div>
                        </div>
                    </div>

                    <div className="mx-auto mt-12 flex max-w-6xl flex-col items-center justify-between gap-4 border-t border-sidebar-border/40 pt-8 text-xs text-sidebar-foreground/50 sm:flex-row">
                        <p>
                            &copy; {new Date().getFullYear()} {BRAND.fullName}.
                            All rights reserved.
                        </p>
                        <p>{BRAND.tagline} · {BRAND.location}</p>
                    </div>
                </footer>
            </div>
        </>
    );
}
