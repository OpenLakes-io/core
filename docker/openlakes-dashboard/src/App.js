import React from 'react';
import {
  ThemeProvider,
  createTheme,
  CssBaseline,
  Container,
  Grid,
  Card,
  CardContent,
  CardActions,
  Button,
  Typography,
  AppBar,
  Toolbar,
  Box,
  Chip,
  Accordion,
  AccordionSummary,
  AccordionDetails,
} from '@mui/material';
import {
  Storage,
  Speed,
  Analytics,
  DataObject,
  Cloud,
  AccountTree,
  Summarize,
  InsertChart,
  Code,
  Widgets,
  Lan,
  ViewModule,
  Dashboard,
  Notifications,
  ShowChart,
  Chat,
  ExpandMore,
  Lock,
} from '@mui/icons-material';

const theme = createTheme({
  palette: {
    mode: 'dark',
    primary: {
      main: '#1976d2',
    },
    secondary: {
      main: '#dc004e',
    },
    background: {
      default: '#0a1929',
      paper: '#1e2a35',
    },
  },
});

// Get configuration from environment variables (injected at runtime)
const config = {
  protocol: window.ENV?.PROTOCOL || 'https',
  domain: window.ENV?.DOMAIN || 'openlakes.dev',
  port: window.ENV?.PORT || '',
};

const dashboardVersion = window.ENV?.VERSION || 'v1.0.1';

const buildServiceUrl = (subdomain, path = '') => {
  if (!subdomain) {
    return '#';
  }
  const portSegment = config.port ? `:${config.port}` : '';
  const baseUrl = `${config.protocol}://${subdomain}.${config.domain}${portSegment}`;
  return path ? `${baseUrl}${path}` : baseUrl;
};

const resolveServiceUrl = (service) => {
  if (service.url) {
    return service.url;
  }
  if (service.host) {
    const portSegment = config.port ? `:${config.port}` : '';
    const baseUrl = `${config.protocol}://${service.host}${portSegment}`;
    return service.path ? `${baseUrl}${service.path}` : baseUrl;
  }
  return buildServiceUrl(service.subdomain, service.path || '');
};

const iconRegistry = {
  storage: Storage,
  speed: Speed,
  analytics: Analytics,
  dataObject: DataObject,
  cloud: Cloud,
  accountTree: AccountTree,
  summarize: Summarize,
  insertChart: InsertChart,
  code: Code,
  widgets: Widgets,
  lan: Lan,
  viewModule: ViewModule,
  dashboard: Dashboard,
  notifications: Notifications,
  showChart: ShowChart,
  chat: Chat,
  default: Widgets,
};

const decodeServicesFromEnv = () => {
  const encoded = window.ENV?.SERVICES_B64;
  if (!encoded) {
    return [];
  }
  try {
    return JSON.parse(window.atob(encoded));
  } catch (err) {
    console.warn('Unable to decode dashboard services payload', err);
    return [];
  }
};

const defaultServicesData = [
  {
    name: 'MinIO Object Storage',
    description: 'S3-compatible object storage for data lake',
    subdomain: 'minio',
    path: '',
    icon: 'storage',
    category: 'Infrastructure',
    color: '#C72C48',
    credentials: { username: 'admin', password: 'admin123' },
  },
  {
    name: 'Alluxio Web UI',
    description: 'Distributed cache and filesystem monitoring',
    subdomain: 'alluxio',
    icon: 'speed',
    category: 'Infrastructure',
    color: '#0081CB',
  },
  {
    name: 'Nessie Catalog',
    description: 'Git-like data catalog for Iceberg tables',
    subdomain: 'nessie',
    icon: 'accountTree',
    category: 'Infrastructure',
    color: '#00A67D',
  },
  {
    name: 'Schema Registry',
    description: 'Apicurio-backed schema registry for Kafka workloads',
    subdomain: 'schema-registry',
    icon: 'dataObject',
    category: 'Infrastructure',
    color: '#8E24AA',
  },
  {
    name: 'Traefik Dashboard',
    description: 'Ingress controller and routing dashboard',
    subdomain: 'traefik',
    path: '/dashboard/',
    icon: 'lan',
    category: 'Infrastructure',
    color: '#37ABC8',
  },
  {
    name: 'Spark Master UI',
    description: 'Apache Spark cluster monitoring',
    subdomain: 'spark',
    icon: 'dataObject',
    category: 'Compute',
    color: '#E25A1C',
  },
  {
    name: 'Spark History',
    description: 'Historical Spark application runs',
    subdomain: 'spark-history',
    icon: 'analytics',
    category: 'Compute',
    color: '#FF7043',
  },
  {
    name: 'Trino Web UI',
    description: 'Distributed SQL query engine',
    subdomain: 'trino',
    icon: 'summarize',
    category: 'Compute',
    color: '#DD00A1',
  },
  {
    name: 'Airflow',
    description: 'Workflow orchestration and scheduling',
    subdomain: 'airflow',
    icon: 'widgets',
    category: 'Orchestration',
    color: '#017CEE',
    credentials: { username: 'admin', password: 'admin' },
  },
  {
    name: 'Superset',
    description: 'Modern data exploration and visualization',
    subdomain: 'superset',
    icon: 'insertChart',
    category: 'Analytics',
    color: '#20A7C9',
    credentials: { username: 'admin', password: 'admin123' },
  },
  {
    name: 'JupyterHub',
    description: 'Multi-user Jupyter notebook server',
    subdomain: 'jupyter',
    icon: 'code',
    category: 'Analytics',
    color: '#F37726',
    credentials: { username: 'admin', password: 'openlakes' },
  },
  {
    name: 'Debezium',
    description: 'CDC and change data capture',
    subdomain: 'debezium',
    icon: 'analytics',
    category: 'Ingestion',
    color: '#FF6600',
  },
  {
    name: 'OpenMetadata',
    description: 'Data catalog and lineage tracking',
    subdomain: 'metadata',
    icon: 'viewModule',
    category: 'Catalog',
    color: '#6366F1',
    credentials: { username: 'admin', password: 'admin' },
  },
  {
    name: 'OpenMetadata Ingestion',
    description: 'Airflow deployment for metadata ingestion jobs',
    subdomain: 'ingestion',
    icon: 'widgets',
    category: 'Catalog',
    color: '#5C6BC0',
  },
  {
    name: 'Grafana',
    description: 'Metrics visualization and monitoring dashboards',
    subdomain: 'grafana',
    icon: 'dashboard',
    category: 'Monitoring',
    color: '#F46800',
    credentials: { username: 'admin', password: 'admin123' },
  },
  {
    name: 'Prometheus',
    description: 'Metrics collection and time-series database',
    subdomain: 'prometheus',
    icon: 'showChart',
    category: 'Monitoring',
    color: '#E6522C',
  },
  {
    name: 'Alertmanager',
    description: 'Alert routing and notification management',
    subdomain: 'alertmanager',
    icon: 'notifications',
    category: 'Monitoring',
    color: '#E6522C',
  },
];

const servicesDataFromEnv = decodeServicesFromEnv();
const services = (servicesDataFromEnv.length ? servicesDataFromEnv : defaultServicesData).map((service) => ({
  ...service,
  url: resolveServiceUrl(service),
}));

const shouldShowCredentials = () => {
  const raw = (window.ENV?.SHOW_CREDENTIALS ?? 'true').toString().toLowerCase();
  return raw !== 'false';
};

const categoryColors = {
  Infrastructure: '#1976d2',
  Compute: '#f57c00',
  Orchestration: '#7b1fa2',
  Analytics: '#0288d1',
  Ingestion: '#00796b',
  Catalog: '#5e35b1',
  Monitoring: '#d32f2f',
};

function App() {
  const categories = [...new Set(services.map((s) => s.category))];
  const showCredentials = shouldShowCredentials();

  return (
    <ThemeProvider theme={theme}>
      <CssBaseline />
      <Box sx={{ flexGrow: 1 }}>
        <AppBar position="static">
          <Toolbar>
            <DataObject sx={{ mr: 2 }} />
            <Typography variant="h6" component="div" sx={{ flexGrow: 1 }}>
              OpenLakes Core Dashboard
            </Typography>
            <Chip
              label={dashboardVersion}
              color="primary"
              variant="outlined"
              size="small"
            />
          </Toolbar>
        </AppBar>

        <Container maxWidth="xl" sx={{ mt: 4, mb: 4 }}>
          <Box sx={{ mb: 4, textAlign: 'center' }}>
            <Typography variant="h4" gutterBottom>
              Welcome to OpenLakes
            </Typography>
            <Typography variant="body1" color="text.secondary">
              A comprehensive Kubernetes-based data platform with storage, compute, streaming, orchestration, analytics, and catalog services.
            </Typography>
          </Box>

          {categories.map((category) => (
            <Box key={category} sx={{ mb: 4 }}>
              <Typography
                variant="h5"
                gutterBottom
                sx={{
                  mb: 2,
                  borderLeft: `4px solid ${categoryColors[category]}`,
                  pl: 2,
                }}
              >
                {category}
              </Typography>
              <Grid container spacing={3}>
                {services
                  .filter((service) => service.category === category)
                  .map((service) => (
                    <Grid item xs={12} sm={6} md={4} key={service.name}>
                      <Card
                        sx={{
                          height: '100%',
                          display: 'flex',
                          flexDirection: 'column',
                          transition: 'transform 0.2s, box-shadow 0.2s',
                          '&:hover': {
                            transform: 'translateY(-4px)',
                            boxShadow: 6,
                          },
                        }}
                      >
                        <CardContent sx={{ flexGrow: 1 }}>
                          <Box
                            sx={{
                              display: 'flex',
                              alignItems: 'center',
                              mb: 2,
                            }}
                          >
                            <Box sx={{ color: service.color, mr: 1 }}>
                              {React.createElement(
                                iconRegistry[service.icon] || iconRegistry.default,
                                { fontSize: 'large' }
                              )}
                            </Box>
                            <Typography variant="h6" component="div">
                              {service.name}
                            </Typography>
                          </Box>
                          <Typography
                            variant="body2"
                            color="text.secondary"
                            sx={{ mb: 1 }}
                          >
                            {service.description}
                          </Typography>
                          <Chip
                            label={service.category}
                            size="small"
                            sx={{
                              backgroundColor: categoryColors[category],
                              color: 'white',
                              mb:
                                showCredentials &&
                                service.credentials &&
                                service.credentials.username &&
                                service.credentials.password
                                  ? 1
                                  : 0,
                            }}
                          />
                          {showCredentials &&
                            service.credentials &&
                            service.credentials.username &&
                            service.credentials.password && (
                            <Accordion
                              sx={{
                                mt: 1,
                                backgroundColor: 'transparent',
                                boxShadow: 'none',
                                '&:before': { display: 'none' },
                              }}
                            >
                              <AccordionSummary
                                expandIcon={<ExpandMore />}
                                sx={{
                                  minHeight: 'auto',
                                  padding: '4px 8px',
                                  '& .MuiAccordionSummary-content': {
                                    margin: '4px 0',
                                  },
                                }}
                              >
                                <Box sx={{ display: 'flex', alignItems: 'center' }}>
                                  <Lock fontSize="small" sx={{ mr: 0.5, fontSize: '14px' }} />
                                  <Typography variant="caption" color="text.secondary">
                                    Login Credentials
                                  </Typography>
                                </Box>
                              </AccordionSummary>
                              <AccordionDetails sx={{ padding: '0 8px 8px 8px' }}>
                                <Box>
                                  <Typography variant="caption" display="block" color="text.secondary">
                                    Username: <strong>{service.credentials.username}</strong>
                                  </Typography>
                                  <Typography variant="caption" display="block" color="text.secondary">
                                    Password: <strong>{service.credentials.password}</strong>
                                  </Typography>
                                </Box>
                              </AccordionDetails>
                            </Accordion>
                          )}
                        </CardContent>
                        <CardActions>
                          <Button
                            size="small"
                            variant="contained"
                            fullWidth
                            href={service.url}
                            target="_blank"
                            rel="noopener noreferrer"
                          >
                            Open Service
                          </Button>
                        </CardActions>
                      </Card>
                    </Grid>
                  ))}
              </Grid>
            </Box>
          ))}

          <Box sx={{ mt: 6, mb: 2, textAlign: 'center' }}>
            <Typography variant="body2" color="text.secondary">
              OpenLakes Core - Comprehensive Kubernetes Data Platform
            </Typography>
            <Typography variant="body2" color="text.secondary">
              Documentation:{' '}
              <a
                href="https://github.com/openlakes/core"
                target="_blank"
                rel="noopener noreferrer"
                style={{ color: '#1976d2' }}
              >
                github.com/openlakes/core
              </a>
            </Typography>
          </Box>
        </Container>
      </Box>
    </ThemeProvider>
  );
}

export default App;
