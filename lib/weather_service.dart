import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'recommendation_service.dart';

class WeatherCity {
  final String name, region, country;
  final double latitude, longitude;
  const WeatherCity(
    this.name,
    this.region,
    this.country,
    this.latitude,
    this.longitude,
  );
  String get label =>
      [name, region, country].where((v) => v.isNotEmpty).join(', ');
  Map<String, Object?> toMap() => {
    'name': name,
    'region': region,
    'country': country,
    'latitude': latitude,
    'longitude': longitude,
  };
  factory WeatherCity.fromMap(Map<String, dynamic> m) {
    final lat = (m['latitude'] as num).toDouble(),
        lon = (m['longitude'] as num).toDouble();
    if (!lat.isFinite || !lon.isFinite || lat.abs() > 90 || lon.abs() > 180) {
      throw const FormatException('Ciudad no válida.');
    }
    return WeatherCity(
      m['name'] as String,
      m['region'] as String? ?? '',
      m['country'] as String? ?? '',
      lat,
      lon,
    );
  }
}

class WeatherDay {
  final String date;
  final double min, max;
  final double? rainProbability, windSpeed;
  const WeatherDay(
    this.date,
    this.min,
    this.max, {
    this.rainProbability,
    this.windSpeed,
  });
  double get temperature => (min + max) / 2;
  Climate get climate => ClimateLabel.fromTemperature(temperature);
  Map<String, Object?> toMap() => {
    'date': date,
    'min': min,
    'max': max,
    'rain': rainProbability,
    'wind': windSpeed,
  };
}

class WeatherForecast {
  final WeatherCity city;
  final DateTime fetchedAt;
  final List<WeatherDay> days;
  const WeatherForecast(this.city, this.fetchedAt, this.days);
  bool get isFresh =>
      DateTime.now().difference(fetchedAt).inMinutes < 15 &&
      !fetchedAt.isAfter(DateTime.now());
  WeatherDay? forDate(DateTime date) {
    for (final d in days) {
      if (d.date == dateKey(date)) return d;
    }
    return null;
  }

  String encode() => jsonEncode({
    'city': city.toMap(),
    'fetchedAt': fetchedAt.toIso8601String(),
    'days': days.map((d) => d.toMap()).toList(),
  });
  static WeatherForecast? decode(String? value) {
    try {
      if (value == null) return null;
      final m = jsonDecode(value) as Map<String, dynamic>;
      return WeatherForecast(
        WeatherCity.fromMap(m['city'] as Map<String, dynamic>),
        DateTime.parse(m['fetchedAt'] as String),
        (m['days'] as List)
            .map(
              (d) => WeatherDay(
                d['date'] as String,
                (d['min'] as num).toDouble(),
                (d['max'] as num).toDouble(),
                rainProbability: (d['rain'] as num?)?.toDouble(),
                windSpeed: (d['wind'] as num?)?.toDouble(),
              ),
            )
            .toList(),
      );
    } catch (_) {
      return null;
    }
  }
}

class ClimatePreferences {
  final bool automatic;
  final Climate manual;
  final WeatherCity? city;
  const ClimatePreferences({
    this.automatic = false,
    this.manual = Climate.mild,
    this.city,
  });
  String encode() => jsonEncode({
    'automatic': automatic,
    'manual': manual.name,
    'city': city?.toMap(),
  });
  static ClimatePreferences decode(String? value) {
    try {
      if (value == null) return const ClimatePreferences();
      final m = jsonDecode(value) as Map<String, dynamic>;
      return ClimatePreferences(
        automatic: m['automatic'] == true,
        manual: Climate.values.firstWhere((c) => c.name == m['manual']),
        city: m['city'] == null
            ? null
            : WeatherCity.fromMap(m['city'] as Map<String, dynamic>),
      );
    } catch (_) {
      return const ClimatePreferences();
    }
  }
}

class WeatherService {
  final http.Client client;
  WeatherService({http.Client? client}) : client = client ?? http.Client();
  Future<List<WeatherCity>> search(String query) async {
    if (query.trim().length < 2) return [];
    final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': query.trim(),
      'count': '8',
      'language': 'es',
      'format': 'json',
    });
    final response = await client.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw const FormatException('No se han podido buscar ciudades.');
    }
    final m = jsonDecode(response.body) as Map<String, dynamic>;
    return ((m['results'] as List?) ?? [])
        .map(
          (r) => WeatherCity(
            r['name'] as String,
            r['admin1'] as String? ?? '',
            r['country'] as String? ?? '',
            (r['latitude'] as num).toDouble(),
            (r['longitude'] as num).toDouble(),
          ),
        )
        .toList();
  }

  Future<WeatherForecast> fetch(WeatherCity city) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': city.latitude.toString(),
      'longitude': city.longitude.toString(),
      'daily': 'temperature_2m_min,temperature_2m_max,precipitation_probability_max,wind_speed_10m_max',
      'wind_speed_unit': 'kmh',
      'timezone': 'auto',
      'forecast_days': '14',
    });
    final response = await client.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw const FormatException(
        'No se ha podido consultar el tiempo. Puedes usar el modo manual.',
      );
    }
    final m = jsonDecode(response.body) as Map<String, dynamic>,
        daily = m['daily'] as Map<String, dynamic>;
    final dates = daily['time'] as List,
        mins = daily['temperature_2m_min'] as List,
        maxs = daily['temperature_2m_max'] as List;
    final days = <WeatherDay>[];
    for (var i = 0; i < dates.length; i++) {
      if (mins[i] is num && maxs[i] is num) {
        days.add(
          WeatherDay(
            dates[i] as String,
            (mins[i] as num).toDouble(),
            (maxs[i] as num).toDouble(),
            rainProbability:
                (daily['precipitation_probability_max']?[i] as num?)
                    ?.toDouble(),
            windSpeed: (daily['wind_speed_10m_max']?[i] as num?)?.toDouble(),
          ),
        );
      }
    }
    if (days.isEmpty) {
      throw const FormatException('No hay previsión disponible.');
    }
    return WeatherForecast(city, DateTime.now(), days);
  }

  void close() => client.close();
}
