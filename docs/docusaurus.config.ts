import { themes as prismThemes } from 'prism-react-renderer';
import type { Config } from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

const config: Config = {
  title: 'Roam for Roku',
  tagline: 'A you-first remote for Roku',
  favicon: 'img/favicon.ico',

  url: 'https://roam.msd3.io',
  baseUrl: '/',

  onBrokenLinks: 'throw',
  onBrokenMarkdownLinks: 'warn',

  i18n: {
    defaultLocale: 'en',
    locales: [
      "en", "ar", "de", "es", "es-419",
      "fil", "fr", "fr-CA", "it", "pa",
      "pt-BR", "pt-PT", "vi", "zh-Hans"
    ],
  },

  presets: [
    [
      'classic',
      {
        docs: false,
        blog: false,

        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],

  themeConfig: {
    // Replace with your project's social card
    image: 'img/docusaurus-social-card.jpg',
    navbar: {
      title: 'Roam',
      logo: {
        alt: 'Roam App Icon',
        src: 'img/roam-icon.png',
        style: {
          "border-radius": "20%"
        }
      },
      items: [
        {
          href: 'https://github.com/msdrigg/roam',
          label: 'GitHub',
          position: 'right',
        },
        {
          type: 'localeDropdown',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          label: 'Github',
          href: 'https://github.com/msdrigg/roam'
        },
        {
          label: 'Discord',
          href: 'https://discord.gg/FqaTNRccbG',
        },
      ],
      copyright: `Copyright © ${new Date().getFullYear()} Scott Driggers`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
