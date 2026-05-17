from setuptools import find_packages, setup

package_name = 'test_pub_simple'

setup(
    name=package_name,
    version='0.1.0',
    packages=find_packages(exclude=['test']),
    data_files=[
        ('share/ament_index/resource_index/packages', ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='ros-snapper',
    maintainer_email='dev@example.com',
    description='Minimal Python publisher for the test/* topics.',
    license='MIT',
    entry_points={
        'console_scripts': [
            'pub_simple = test_pub_simple.pub_simple:main',
        ],
    },
)
