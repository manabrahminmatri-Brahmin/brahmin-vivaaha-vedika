/// Location Service to get coordinates from place of birth
/// This is important for accurate birth chart calculations
library;

class LocationService {
  /// Get coordinates (latitude, longitude) from place of birth
  /// Uses a lookup table for major Indian cities
  static Map<String, double> getCoordinatesFromPlace({
    required String? placeOfBirth,
    String? country,
    String? state,
  }) {
    // Default to Hyderabad if not specified
    if (placeOfBirth == null || placeOfBirth.isEmpty) {
      return {'latitude': 17.3850, 'longitude': 78.4867};
    }
    
    final place = placeOfBirth.toLowerCase().trim();
    final stateName = state?.toLowerCase().trim() ?? '';
    
    // Major cities in India with coordinates
    final cityCoordinates = <String, Map<String, double>>{
      // Andhra Pradesh
      'hyderabad': {'latitude': 17.3850, 'longitude': 78.4867},
      'visakhapatnam': {'latitude': 17.6868, 'longitude': 83.2185},
      'vijayawada': {'latitude': 16.5062, 'longitude': 80.6480},
      // Amaravati capital region (Guntur district); also common spelling Amaravathi
      'amaravati': {'latitude': 16.5083, 'longitude': 80.5180},
      'amaravathi': {'latitude': 16.5083, 'longitude': 80.5180},
      'guntur': {'latitude': 16.3067, 'longitude': 80.4365},
      'nellore': {'latitude': 14.4426, 'longitude': 79.9865},
      'kurnool': {'latitude': 15.8281, 'longitude': 78.0373},
      'rajahmundry': {'latitude': 17.0005, 'longitude': 81.8040},
      'tirupati': {'latitude': 13.6288, 'longitude': 79.4192},
      'kakinada': {'latitude': 16.9891, 'longitude': 82.2475},
      'kadapa': {'latitude': 14.4664, 'longitude': 78.8238},
      
      // Telangana
      'warangal': {'latitude': 18.0000, 'longitude': 79.5833},
      'nizamabad': {'latitude': 18.6725, 'longitude': 78.0941},
      'karimnagar': {'latitude': 18.4386, 'longitude': 79.1288},
      
      // Tamil Nadu
      'chennai': {'latitude': 13.0827, 'longitude': 80.2707},
      'coimbatore': {'latitude': 11.0168, 'longitude': 76.9558},
      'madurai': {'latitude': 9.9252, 'longitude': 78.1198},
      'salem': {'latitude': 11.6643, 'longitude': 78.1460},
      'tiruchirappalli': {'latitude': 10.7905, 'longitude': 78.7047},
      'vellore': {'latitude': 12.9165, 'longitude': 79.1325},
      
      // Karnataka
      'bangalore': {'latitude': 12.9716, 'longitude': 77.5946},
      'mysore': {'latitude': 12.2958, 'longitude': 76.6394},
      'mangalore': {'latitude': 12.9141, 'longitude': 74.8560},
      'hubli': {'latitude': 15.3647, 'longitude': 75.1240},
      
      // Maharashtra
      'mumbai': {'latitude': 19.0760, 'longitude': 72.8777},
      'pune': {'latitude': 18.5204, 'longitude': 73.8567},
      'nagpur': {'latitude': 21.1458, 'longitude': 79.0882},
      'aurangabad': {'latitude': 19.8762, 'longitude': 75.3433},
      
      // Delhi
      'delhi': {'latitude': 28.6139, 'longitude': 77.2090},
      'new delhi': {'latitude': 28.6139, 'longitude': 77.2090},
      
      // West Bengal
      'kolkata': {'latitude': 22.5726, 'longitude': 88.3639},
      'howrah': {'latitude': 22.5958, 'longitude': 88.2636},
      
      // Gujarat
      'ahmedabad': {'latitude': 23.0225, 'longitude': 72.5714},
      'surat': {'latitude': 21.1702, 'longitude': 72.8311},
      'vadodara': {'latitude': 22.3072, 'longitude': 73.1812},
      
      // Rajasthan
      'jaipur': {'latitude': 26.9124, 'longitude': 75.7873},
      'udaipur': {'latitude': 24.5854, 'longitude': 73.7125},
      
      // Kerala
      'kochi': {'latitude': 9.9312, 'longitude': 76.2673},
      'thiruvananthapuram': {'latitude': 8.5241, 'longitude': 76.9366},
      'calicut': {'latitude': 11.2588, 'longitude': 75.7804},
      
      // Odisha
      'bhubaneswar': {'latitude': 20.2961, 'longitude': 85.8245},
      'cuttack': {'latitude': 20.4625, 'longitude': 85.8829},
      
      // Punjab
      'chandigarh': {'latitude': 30.7333, 'longitude': 76.7794},
      'amritsar': {'latitude': 31.6340, 'longitude': 74.8723},
      
      // Haryana
      'gurgaon': {'latitude': 28.4089, 'longitude': 77.0378},
      'faridabad': {'latitude': 28.4089, 'longitude': 77.3178},
    };
    
    // Try exact match first
    if (cityCoordinates.containsKey(place)) {
      return cityCoordinates[place]!;
    }
    
    // Try partial match
    for (final entry in cityCoordinates.entries) {
      if (place.contains(entry.key) || entry.key.contains(place)) {
        return entry.value;
      }
    }
    
    // Try state-based defaults
    final stateDefaults = <String, Map<String, double>>{
      'andhra pradesh': {'latitude': 17.3850, 'longitude': 78.4867}, // Hyderabad
      'telangana': {'latitude': 17.3850, 'longitude': 78.4867}, // Hyderabad
      'tamil nadu': {'latitude': 13.0827, 'longitude': 80.2707}, // Chennai
      'karnataka': {'latitude': 12.9716, 'longitude': 77.5946}, // Bangalore
      'maharashtra': {'latitude': 19.0760, 'longitude': 72.8777}, // Mumbai
      'west bengal': {'latitude': 22.5726, 'longitude': 88.3639}, // Kolkata
      'gujarat': {'latitude': 23.0225, 'longitude': 72.5714}, // Ahmedabad
      'rajasthan': {'latitude': 26.9124, 'longitude': 75.7873}, // Jaipur
      'kerala': {'latitude': 9.9312, 'longitude': 76.2673}, // Kochi
      'odisha': {'latitude': 20.2961, 'longitude': 85.8245}, // Bhubaneswar
      'punjab': {'latitude': 30.7333, 'longitude': 76.7794}, // Chandigarh
      'haryana': {'latitude': 28.4089, 'longitude': 77.0378}, // Gurgaon
    };
    
    if (stateName.isNotEmpty && stateDefaults.containsKey(stateName)) {
      return stateDefaults[stateName]!;
    }
    
    // Default to Hyderabad
    return {'latitude': 17.3850, 'longitude': 78.4867};
  }
}
