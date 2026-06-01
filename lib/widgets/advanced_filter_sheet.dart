import 'package:flutter/material.dart';
import '../models/advanced_filter.dart';

/// Bottom sheet for advanced filtering
class AdvancedFilterSheet extends StatefulWidget {
  final AdvancedFilter currentFilter;
  final Function(AdvancedFilter) onApply;

  const AdvancedFilterSheet({
    super.key,
    required this.currentFilter,
    required this.onApply,
  });

  @override
  State<AdvancedFilterSheet> createState() => _AdvancedFilterSheetState();
}

class _AdvancedFilterSheetState extends State<AdvancedFilterSheet>
    with SingleTickerProviderStateMixin {
  late AdvancedFilter _filter;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _filter = widget.currentFilter;
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.filter_list, size: 28),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Advanced Filters',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (_filter.isActive)
                      TextButton(
                        onPressed: _clearAll,
                        child: const Text('Clear All'),
                      ),
                  ],
                ),
              ),
              // Active filters chips
              if (_filter.isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  height: 50,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: _buildActiveFilterChips(),
                  ),
                ),
              // Tabs
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: const [
                  Tab(text: 'Career'),
                  Tab(text: 'Lifestyle'),
                  Tab(text: 'Religion'),
                  Tab(text: 'Profile'),
                ],
              ),
              // Tab content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildCareerTab(),
                    _buildLifestyleTab(),
                    _buildReligionTab(),
                    _buildProfileTab(),
                  ],
                ),
              ),
              // Bottom buttons
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(10),
                      blurRadius: 4,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () {
                          widget.onApply(_filter);
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(
                          _filter.isActive
                              ? 'Apply ${_filter.activeCount} Filter${_filter.activeCount != 1 ? 's' : ''}'
                              : 'Apply Filters',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildActiveFilterChips() {
    final chips = <Widget>[];
    
    if (_filter.educationLevel != null) {
      chips.add(_buildChip('Education: ${_filter.educationLevel}', () {
        setState(() => _filter = _filter.copyWith(clearEducationLevel: true));
      }));
    }
    if (_filter.occupation != null) {
      chips.add(_buildChip('Job: ${_filter.occupation}', () {
        setState(() => _filter = _filter.copyWith(clearOccupation: true));
      }));
    }
    if (_filter.minSalary != null || _filter.maxSalary != null) {
      chips.add(_buildChip(
          'Salary: ${_filter.minSalary?.toStringAsFixed(0) ?? '0'} - ${_filter.maxSalary?.toStringAsFixed(0) ?? '∞'}L',
          () => setState(() => _filter = _filter.copyWith(
                clearMinSalary: true,
                clearMaxSalary: true,
              ))));
    }
    if (_filter.diet != null) {
      chips.add(_buildChip('Diet: ${_filter.diet}', () {
        setState(() => _filter = _filter.copyWith(clearDiet: true));
      }));
    }
    if (_filter.maritalStatus != null) {
      chips.add(_buildChip('Status: ${_filter.maritalStatus}', () {
        setState(() => _filter = _filter.copyWith(maritalStatus: null));
      }));
    }
    if (_filter.verifiedOnly == true) {
      chips.add(_buildChip('Verified Only', () {
        setState(() => _filter = _filter.copyWith(verifiedOnly: null));
      }));
    }
    if (_filter.premiumOnly == true) {
      chips.add(_buildChip('Premium Only', () {
        setState(() => _filter = _filter.copyWith(premiumOnly: null));
      }));
    }
    
    return chips;
  }

  Widget _buildChip(String label, VoidCallback onRemove) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Chip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        deleteIcon: const Icon(Icons.close, size: 18),
        onDeleted: onRemove,
        backgroundColor: Theme.of(context).primaryColor.withAlpha(20),
        side: BorderSide(color: Theme.of(context).primaryColor.withAlpha(50)),
      ),
    );
  }

  Widget _buildCareerTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Education & Career'),
          const SizedBox(height: 12),
          _buildDropdown(
            'Education Level',
            _filter.educationLevel,
            FilterOptions.educationLevels,
            (value) => setState(() => _filter = _filter.copyWith(educationLevel: value)),
          ),
          const SizedBox(height: 16),
          _buildDropdown(
            'Occupation',
            _filter.occupation,
            FilterOptions.occupations,
            (value) => setState(() => _filter = _filter.copyWith(occupation: value)),
          ),
          const SizedBox(height: 16),
          _buildDropdown(
            'Employment Type',
            _filter.employmentType,
            FilterOptions.employmentTypes,
            (value) => setState(() => _filter = _filter.copyWith(employmentType: value)),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('Annual Income (Lakhs)'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildNumberField(
                  'Min',
                  _filter.minSalary?.toString(),
                  (value) => setState(() => _filter = _filter.copyWith(
                    minSalary: value != null ? double.tryParse(value) : null,
                  )),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('to'),
              ),
              Expanded(
                child: _buildNumberField(
                  'Max',
                  _filter.maxSalary?.toString(),
                  (value) => setState(() => _filter = _filter.copyWith(
                    maxSalary: value != null ? double.tryParse(value) : null,
                  )),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLifestyleTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Lifestyle'),
          const SizedBox(height: 12),
          _buildDropdown(
            'Diet',
            _filter.diet,
            FilterOptions.diets,
            (value) => setState(() => _filter = _filter.copyWith(diet: value)),
          ),
          const SizedBox(height: 16),
          _buildDropdown(
            'Smoking',
            _filter.smoking,
            FilterOptions.smokingOptions,
            (value) => setState(() => _filter = _filter.copyWith(smoking: value)),
          ),
          const SizedBox(height: 16),
          _buildDropdown(
            'Drinking',
            _filter.drinking,
            FilterOptions.drinkingOptions,
            (value) => setState(() => _filter = _filter.copyWith(drinking: value)),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('Physical'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildNumberField(
                  'Min Height (cm)',
                  _filter.minHeight?.toString(),
                  (value) => setState(() => _filter = _filter.copyWith(
                    minHeight: value != null ? int.tryParse(value) : null,
                  )),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('to'),
              ),
              Expanded(
                child: _buildNumberField(
                  'Max Height (cm)',
                  _filter.maxHeight?.toString(),
                  (value) => setState(() => _filter = _filter.copyWith(
                    maxHeight: value != null ? int.tryParse(value) : null,
                  )),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildDropdown(
            'Body Type',
            _filter.bodyType,
            FilterOptions.bodyTypes,
            (value) => setState(() => _filter = _filter.copyWith(bodyType: value)),
          ),
        ],
      ),
    );
  }

  Widget _buildReligionTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Religion & Culture'),
          const SizedBox(height: 12),
          _buildDropdown(
            'Religion',
            _filter.religion,
            FilterOptions.religions,
            (value) => setState(() => _filter = _filter.copyWith(religion: value)),
          ),
          const SizedBox(height: 16),
          _buildTextField(
            'Caste',
            _filter.caste,
            (value) => setState(() => _filter = _filter.copyWith(caste: value)),
          ),
          const SizedBox(height: 16),
          _buildTextField(
            'Mother Tongue',
            _filter.motherTongue,
            (value) => setState(() => _filter = _filter.copyWith(motherTongue: value)),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('Astrology'),
          const SizedBox(height: 12),
          _buildTextField(
            'Nakshatra',
            _filter.nakshatra,
            (value) => setState(() => _filter = _filter.copyWith(nakshatra: value)),
          ),
          const SizedBox(height: 16),
          _buildTextField(
            'Rashi',
            _filter.rashi,
            (value) => setState(() => _filter = _filter.copyWith(rashi: value)),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Profile Quality'),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Verified Users Only'),
            subtitle: const Text('Show only document-verified profiles'),
            value: _filter.verifiedOnly ?? false,
            onChanged: (value) => setState(() =>
                _filter = _filter.copyWith(verifiedOnly: value)),
          ),
          SwitchListTile(
            title: const Text('Premium Users Only'),
            subtitle: const Text('Show only premium/paid members'),
            value: _filter.premiumOnly ?? false,
            onChanged: (value) => setState(() =>
                _filter = _filter.copyWith(premiumOnly: value)),
          ),
          SwitchListTile(
            title: const Text('With Photo Only'),
            subtitle: const Text('Show only profiles with photos'),
            value: _filter.withPhoto ?? false,
            onChanged: (value) => setState(() =>
                _filter = _filter.copyWith(withPhoto: value)),
          ),
          SwitchListTile(
            title: const Text('With Horoscope Only'),
            subtitle: const Text('Show only profiles with birth chart'),
            value: _filter.withHoroscope ?? false,
            onChanged: (value) => setState(() =>
                _filter = _filter.copyWith(withHoroscope: value)),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('Activity'),
          const SizedBox(height: 12),
          _buildDropdown(
            'Last Active',
            _filter.lastActive,
            FilterOptions.lastActiveOptions,
            (value) => setState(() => _filter = _filter.copyWith(lastActive: value)),
            labelBuilder: (v) => FilterOptions.getLabel(v, 'last_active'),
          ),
          const SizedBox(height: 16),
          _buildDropdown(
            'Joined Date',
            _filter.joinedDate,
            FilterOptions.joinedDateOptions,
            (value) => setState(() => _filter = _filter.copyWith(joinedDate: value)),
            labelBuilder: (v) => FilterOptions.getLabel(v, 'joined_date'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).primaryColor,
      ),
    );
  }

  Widget _buildDropdown(
    String label,
    String? value,
    List<String> options,
    Function(String?) onChanged, {
    String Function(String)? labelBuilder,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('Any')),
        ...options.map((option) => DropdownMenuItem(
          value: option,
          child: Text(labelBuilder?.call(option) ?? option),
        )),
      ],
      onChanged: onChanged,
    );
  }

  Widget _buildTextField(
    String label,
    String? value,
    Function(String?) onChanged,
  ) {
    return TextField(
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      controller: TextEditingController(text: value ?? ''),
      onChanged: onChanged,
    );
  }

  Widget _buildNumberField(
    String label,
    String? value,
    Function(String?) onChanged,
  ) {
    return TextField(
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      keyboardType: TextInputType.number,
      controller: TextEditingController(text: value ?? ''),
      onChanged: onChanged,
    );
  }

  void _clearAll() {
    setState(() => _filter = AdvancedFilter.empty());
  }
}

/// Button to show advanced filter sheet
class AdvancedFilterButton extends StatelessWidget {
  final AdvancedFilter currentFilter;
  final Function(AdvancedFilter) onApply;

  const AdvancedFilterButton({
    super.key,
    required this.currentFilter,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () => _showFilterSheet(context),
      icon: const Icon(Icons.filter_list),
      label: Text(
        currentFilter.isActive
            ? 'Filters (${currentFilter.activeCount})'
            : 'Filters',
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: currentFilter.isActive
            ? Theme.of(context).primaryColor
            : Colors.grey[200],
        foregroundColor: currentFilter.isActive ? Colors.white : Colors.black87,
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AdvancedFilterSheet(
        currentFilter: currentFilter,
        onApply: onApply,
      ),
    );
  }
}
