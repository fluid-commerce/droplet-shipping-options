import React from 'react';
import { createRoot } from 'react-dom/client';
import RateEditor from '~/components/RateEditor/RateEditor';

const rootElement = document.getElementById('rate-editor-root');

if (rootElement) {
  const apiBasePath = rootElement.dataset.apiBasePath || '/api/rates';
  const dri = rootElement.dataset.dri || '';
  const backUrl = rootElement.dataset.backUrl || '/rate_tables';

  const root = createRoot(rootElement);
  root.render(
    <RateEditor
      apiBasePath={apiBasePath}
      dri={dri}
      backUrl={backUrl}
    />
  );
}
