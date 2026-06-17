from setuptools import find_packages, setup

package_name = "rokey_cobot1"

setup(
    name=package_name,
    version="0.0.0",
    packages=find_packages(exclude=["test"]),
    data_files=[
        ("share/ament_index/resource_index/packages", ["resource/" + package_name]),
        ("share/" + package_name, ["package.xml"]),
    ],
    install_requires=["setuptools"],
    zip_safe=True,
    maintainer="juwan",
    maintainer_email="dlacksdn352@gmail.com",
    description="ROKEY BOOT CAMP Package",
    license="Apache 2.0 License",
    entry_points={
        "console_scripts": [
            "simple_amove=rokey_cobot1.basic.amove_test:main",
            "force_control = rokey_cobot1.basic.force_control:main",
            "get_current_pos=rokey_cobot1.basic.get_current_pos:main",
            "getting_position = rokey_cobot1.basic.getting_position:main",
            "grip=rokey_cobot1.basic.grip:main",
            "jog = rokey_cobot1.basic.jog_complete:main",
            "move_periodic = rokey_cobot1.basic.move_periodic:main",
            "simple_move=rokey_cobot1.basic.move:main",
            "simple_movesx=rokey_cobot1.basic.movesx_test:main",
            "data_recording=rokey_cobot1.basic.data_recording:main"
        ],
    },
)
